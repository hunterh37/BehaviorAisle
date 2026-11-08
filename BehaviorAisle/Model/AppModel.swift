import Foundation
import Observation
import RealityKit
import SwiftUI
import simd
import HumanCore

/// App state and the simulation loop: shoppers ask the predictor, walk, pick, repeat.
@MainActor
@Observable
final class AppModel {
    var catalog: [Product] = Catalog.laidOut()
    var shoppers: [ShopperAgent] = []
    var mode: PredictorMode = PredictorMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? AppModel.defaultMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    var proxyURL: String = UserDefaults.standard.string(forKey: "proxyURL") ?? AppModel.defaultProxy {
        didSet { UserDefaults.standard.set(proxyURL, forKey: "proxyURL") }
    }
    /// Empty proxy URL = call Unbox directly from the app with the bundled or Settings key.
    static let defaultProxy = ""
    static let defaultMode = PredictorMode.live
    /// Shelf stock density; `applyDensity()` rebuilds the store with it.
    var density = StoreDensity.load() {
        didSet { density.save() }
    }
    @ObservationIgnored var storeHost = Entity()
    var showArcs = true
    var showCards = true
    var showAnomaly = true
    /// Destination path, shelf beacon and intent panel for imported shoppers.
    var showIntent = true {
        didSet { for s in shoppers { intents.update(s, catalog: catalog, visible: showIntent) } }
    }
    var heatmapOn = false
    var heatmapBusy = false
    var immersiveOpen = false
    /// Scene generation progress 0...1; nil when no build is running.
    var loadProgress: Double?
    var loadStage = ""
    var forkId: String?
    var status = "Ready"
    var lastWhatIf: String?
    /// Paired counterfactual for the last what-if change (heuristic, 10 x 30 shoppers).
    var whatIfResult: Experiment.WhatIf?
    var whatIfItem: String?
    var whatIfBusy = false
    var callCount = 0
    /// Profile import pipeline state for ProfileImportView.
    var importStage: ImportStage = .idle
    var showAnalysis = false
    /// Control window section to scroll to (demo routes and verdict taps).
    var scrollTarget: String?
    var importedProfile: TwitterProfile?
    var importedTraits: ProfileTraits?
    var importedPersonas: [Persona] = []
    @ObservationIgnored var importTask: Task<Void, Never>?

    @ObservationIgnored var store: StoreBuilder.Built?
    @ObservationIgnored let vizRoot = Entity()
    @ObservationIgnored var arcs = ArcLayer()
    @ObservationIgnored var ghosts = GhostLayer()
    @ObservationIgnored var heatmap = HeatmapLayer()
    @ObservationIgnored let intents = IntentLayer()

    /// Cached so each prediction request skips a synchronous Keychain read on the main thread.
    @ObservationIgnored private var cachedToken: String?
    var token: String {
        get {
            if let t = cachedToken { return t }
            let t = Keychain.get("proxyToken") ?? ""
            cachedToken = t
            return t
        }
        set { cachedToken = newValue; Keychain.set(newValue, for: "proxyToken") }
    }

    var predictor: RoutedPredictor {
        let live: (any Predictor)?
        if let url = URL(string: proxyURL), url.scheme?.hasPrefix("http") == true {
            live = BehaviorGPTPredictor(endpoint: url, token: token)
        } else {
            let key = token.isEmpty ? UnboxPredictor.bundledKey : token
            live = key.isEmpty ? nil : UnboxPredictor(apiKey: key)
        }
        return RoutedPredictor(mode: mode, live: live, heuristic: heuristic)
    }

    var heuristic: HeuristicPredictor {
        var h = HeuristicPredictor()
        for p in importedPersonas { h.personas[p.id] = p }
        return h
    }

    func product(_ id: String) -> Product? { catalog.first { $0.id == id } }
    func shopper(_ id: String) -> ShopperAgent? { shoppers.first { $0.id == id } }

    // MARK: Scene

    func buildScene(into content: RealityViewContent) async -> Entity {
        loadProgress = 0
        let built = await StoreBuilder.build(catalog: catalog, density: density) { [weak self] f, stage in
            self?.loadProgress = f
            self?.loadStage = stage
        }
        store = built
        built.root.addChild(vizRoot)
        vizRoot.addChild(arcs.root)
        vizRoot.addChild(ghosts.root)
        vizRoot.addChild(heatmap.root)
        vizRoot.addChild(intents.root)
        // Reopening the space rebuilds the store; drop the previous one so two stores never render.
        storeHost.children.removeAll()
        storeHost.addChild(built.root)
        content.add(storeHost)
        loadProgress = nil
        Task { await spawnShoppers() }
        return built.root
    }

    /// Rebuilds the store shell and shelves at the current density; shoppers and viz layers move over.
    func applyDensity() async {
        guard let old = store, loadProgress == nil else { return }
        loadProgress = 0
        let built = await StoreBuilder.build(catalog: catalog, density: density) { [weak self] f, stage in
            self?.loadProgress = f
            self?.loadStage = stage
        }
        built.root.addChild(vizRoot)
        for s in shoppers { built.root.addChild(s.root) }
        old.root.removeFromParent()
        storeHost.addChild(built.root)
        store = built
        loadProgress = nil
    }

    func spawnShoppers() async {
        shoppers.forEach { $0.root.removeFromParent() }
        let imported = shoppers.filter { $0.traits != nil }
        shoppers = Persona.all.enumerated().map { ShopperAgent(persona: $1, index: $0) }
        for s in shoppers {
            store?.root.addChild(s.root)
            await s.loadBody()
            request(s)
        }
        for old in imported {
            guard let t = old.traits, let p = old.profile else { continue }
            await spawnImported(p, t)
        }
    }

    // MARK: Profile import

    enum ImportStage: Equatable {
        case idle, fetching, reading, classifying, building, done
        case failed(String)
    }

    func importProfile(_ input: String) {
        let handle = ProfileClient.normalize(input)
        guard !handle.isEmpty else { importStage = .failed("Enter an X handle"); return }
        importTask?.cancel()
        importedProfile = nil
        importedTraits = nil
        importStage = .fetching
        let client = ProfileClient(predictURL: proxyURL, token: token)
        let cat = catalog
        importTask = Task {
            do {
                guard let client else { throw ProfileError.noProxy }
                let profile = try await client.profile(handle)
                try Task.checkCancellation()
                importedProfile = profile
                importStage = .reading
                try await Task.sleep(for: .seconds(1.6 + Double(min(profile.tweets.count, 6)) * 0.35))
                importStage = .classifying
                let traits: ProfileTraits
                do { traits = try await client.classify(profile, catalog: cat) } catch {
                    traits = ProfileTraits.heuristic(profile, catalog: cat)
                }
                try Task.checkCancellation()
                importedTraits = traits
                importStage = .building
                await spawnImported(profile, traits)
                importStage = .done
            } catch is CancellationError {
            } catch {
                importStage = .failed(error.localizedDescription)
            }
        }
    }

    /// Adds (or replaces) the profile's shopper at the entrance with its HumanHD body and thought cloud.
    func spawnImported(_ profile: TwitterProfile, _ traits: ProfileTraits) async {
        let persona = traits.persona(for: profile)
        importedPersonas.removeAll { $0.id == persona.id }
        importedPersonas.append(persona)
        for old in shoppers where old.persona.id == persona.id { old.root.removeFromParent(); intents.clear(old.id) }
        shoppers.removeAll { $0.persona.id == persona.id }
        let spec: HumanSpec? = traits.body.confidence > 0.2
            ? HumanTraitsMapper.spec(traits.body, seed: persona.skinSeed)
            : nil
        let s = ShopperAgent(persona: persona, index: shoppers.count, spec: spec)
        s.profile = profile
        s.traits = traits
        shoppers.append(s)
        status = "Imported @\(profile.handle)"
        guard let store else { return }
        store.root.addChild(s.root)
        await s.loadBody()
        let cloud = ThoughtCloud()
        s.root.addChild(cloud.root)
        s.cloud = cloud
        await cloud.show(traits.wishlist.compactMap(product))
        request(s)
    }


    func reset() {
        catalog = Catalog.laidOut()
        for p in catalog { store?.slots[p.id]?.position = p.anchor - SIMD3(0, 0.12, 0) }
        refreshSaleSigns()
        forkId = nil
        ghosts.clear()
        lastWhatIf = nil
        whatIfResult = nil
        whatIfItem = nil
        Task { await spawnShoppers() }
    }

    // MARK: Loop

    func tick(_ dt: Float) {
        for s in shoppers {
            switch s.phase {
            case .walking:
                if s.step(dt) { arrive(s) }
            case .picking:
                guard !s.frozen else { continue }
                s.timer -= dt
                if s.timer <= 0 { finishPick(s) }
            case .checkingOut:
                if s.step(dt) || s.path.isEmpty {
                    s.timer -= dt
                    if s.timer <= 0 { s.phase = .done; s.express(.smile) }
                }
            case .thinking, .done:
                _ = s.step(dt)
            }
        }
        for s in shoppers { s.cloud?.tick(dt) }
        intents.tick(dt)
        ghosts.tick(dt)
        if showCards { arcs.follow(shoppers) }
    }

    func request(_ s: ShopperAgent) {
        s.phase = .thinking
        s.requestId += 1
        let rid = s.requestId
        let req = PredictionRequest(personaId: s.persona.id, history: s.history, cart: s.cart, catalog: catalog.filter(\.inStock))
        let pred = predictor
        callCount += 1
        s.baseline = heuristic.rank(req, from: s.position).predictions
        Task {
            let result: PredictionResult
            do { result = try await pred.predict(req) } catch {
                result = heuristic.rank(req, from: nil)
            }
            guard rid == s.requestId else { return }
            apply(result, to: s)
        }
    }

    func apply(_ r: PredictionResult, to s: ShopperAgent) {
        s.predictions = r.predictions
        s.source = r.source
        if showAnomaly { s.anomaly = r.anomaly }
        status = "\(s.persona.name): \(r.source)"
        arcs.update(s, catalog: catalog, visible: showArcs)
        intents.update(s, catalog: catalog, visible: showIntent)
        if forkId == s.id { ghosts.spawn(for: s, catalog: catalog) }
        guard !s.frozen else { return }
        execute(s)
    }

    func execute(_ s: ShopperAgent) {
        guard let choice = s.choose() else { return }
        s.target = choice
        intents.update(s, catalog: catalog, visible: showIntent)
        if choice.action == .checkout || choice.itemId == Prediction.checkoutId {
            s.path = StoreLayout.path(from: s.position, to: StoreLayout.checkoutStand)
            s.phase = .checkingOut
            s.timer = 2.5
            s.look(at: StoreLayout.checkout + SIMD3(0, 1, 0))
            return
        }
        guard let p = product(choice.itemId) else { return }
        s.walk(to: p.stand)
    }

    func arrive(_ s: ShopperAgent) {
        guard let t = s.target, let p = product(t.itemId) else { request(s); return }
        s.phase = .picking
        s.timer = t.action == .addToCart ? 1.4 : 0.9
        s.look(at: p.anchor)
        s.express(t.action == .addToCart ? .smile : .thinking)
    }

    func finishPick(_ s: ShopperAgent) {
        guard let t = s.target else { request(s); return }
        s.history.append(BehaviorEvent(t.action, t.itemId))
        let rank = s.predictions.firstIndex { $0.id == t.id } ?? s.predictions.count
        s.log.append(.init(itemId: t.itemId, action: t.action, p: t.p, rank: rank, source: s.source))
        if t.action == .addToCart { s.cart.append(t.itemId) }
        s.look(at: nil)
        s.express(.neutral)
        request(s)
    }

    // MARK: Fork view

    func toggleFreeze(_ id: String) {
        guard let s = shopper(id) else { return }
        if forkId == id {
            s.frozen = false
            forkId = nil
            ghosts.clear()
            if s.phase == .thinking || s.path.isEmpty { execute(s) }
        } else {
            if let old = forkId.flatMap(shopper) { old.frozen = false }
            s.frozen = true
            forkId = id
            ghosts.spawn(for: s, catalog: catalog)
        }
    }

    // MARK: What-if merchandising

    func moveProduct(_ id: String, to world: SIMD3<Float>) {
        guard let i = catalog.firstIndex(where: { $0.id == id }) else { return }
        let before = catalog
        defer { measureWhatIf(before, item: id) }
        let row = StoreLayout.gondolaRows.min { abs($0 - world.x) < abs($1 - world.x) } ?? 0
        let side: Float = world.x < row ? -1 : 1
        let z = min(StoreLayout.runStart, max(StoreLayout.runEnd, world.z))
        let y = StoreLayout.shelfLevels.min { abs($0 - (world.y - 0.12)) < abs($1 - (world.y - 0.12)) } ?? 0.95
        catalog[i].anchor = SIMD3(row + side * StoreLayout.gondolaDepth / 2, y + 0.12, z)
        catalog[i].stand = SIMD3(row + side, 0, z)
        store?.slots[id]?.position = catalog[i].anchor - SIMD3(0, 0.12, 0)
        lastWhatIf = "Moved \(catalog[i].name)"
        requery()
    }

    func toggleSale(_ id: String) {
        guard let i = catalog.firstIndex(where: { $0.id == id }) else { return }
        let before = catalog
        defer { measureWhatIf(before, item: id) }
        catalog[i].onSale.toggle()
        lastWhatIf = (catalog[i].onSale ? "Sale on " : "Sale off ") + catalog[i].name
        refreshSaleSigns()
        requery()
    }

    /// Empties or restocks a SKU's shelf slot; shoppers re-plan without it.
    func toggleStock(_ id: String) {
        guard let i = catalog.firstIndex(where: { $0.id == id }) else { return }
        let before = catalog
        defer { measureWhatIf(before, item: id) }
        catalog[i].inStock.toggle()
        store?.slots[id]?.isEnabled = catalog[i].inStock
        lastWhatIf = (catalog[i].inStock ? "Restocked " : "Out of stock: ") + catalog[i].name
        requery()
    }

    /// Runs the before/after layouts on the same seeded shoppers and stores the per-SKU effect.
    func measureWhatIf(_ before: [Product], item: String) {
        let after = catalog
        whatIfBusy = true
        whatIfItem = item
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                Experiment.whatIf(base: before, variant: after, replicates: 30, shoppers: 50)
            }.value
            guard whatIfItem == item else { return }
            whatIfResult = r
            whatIfBusy = false
        }
    }

    // MARK: Plan test

    /// Whole-plan test: the opening layout vs every move and sale made since, on the same seeded shoppers.
    var planResult: Experiment.WhatIf?
    var planBusy = false
    var planChanges: Int {
        let base = Dictionary(uniqueKeysWithValues: Catalog.laidOut().map { ($0.id, $0) })
        return catalog.filter { p in base[p.id].map { $0.anchor != p.anchor || $0.onSale != p.onSale || $0.inStock != p.inStock } ?? true }.count
    }

    func runPlanTest() {
        let before = Catalog.laidOut(), after = catalog
        planBusy = true
        Task {
            planResult = await Task.detached(priority: .userInitiated) {
                Experiment.whatIf(base: before, variant: after, replicates: 40, shoppers: 50)
            }.value
            planBusy = false
        }
    }

    /// Restores the opening layout and removes sale signs.
    func resetPlan() {
        catalog = Catalog.laidOut()
        for p in catalog {
            store?.slots[p.id]?.position = p.anchor - SIMD3(0, 0.12, 0)
            store?.slots[p.id]?.isEnabled = true
        }
        refreshSaleSigns()
        planResult = nil
        whatIfResult = nil
        lastWhatIf = nil
        requery()
    }

    func refreshSaleSigns() {
        for p in catalog {
            guard let slot = store?.slots[p.id] else { continue }
            let existing = slot.findEntity(named: "sale")
            if p.onSale, existing == nil { slot.addChild(SaleSign.make(price: p.price)) }
            if !p.onSale { existing?.removeFromParent() }
        }
    }

    func requery() {
        for s in shoppers where s.phase != .done && s.phase != .checkingOut { request(s) }
    }

    // MARK: Heatmap

    func runHeatmap() {
        heatmapBusy = true
        let cat = catalog
        Task {
            let grid = await Task.detached(priority: .userInitiated) { HeatmapSim.run(catalog: cat, shoppers: 50) }.value
            await heatmap.show(grid)
            heatmapOn = true
            heatmapBusy = false
        }
    }

    func hideHeatmap() {
        heatmap.root.children.removeAll()
        heatmapOn = false
    }
}
