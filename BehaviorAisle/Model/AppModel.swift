import Foundation
import Observation
import RealityKit
import SwiftUI
import simd

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
    #if targetEnvironment(simulator)
    static let defaultProxy = "http://127.0.0.1:8787/predict"
    static let defaultMode = PredictorMode.live
    #else
    static let defaultProxy = ""
    static let defaultMode = PredictorMode.heuristic
    #endif
    var showArcs = true
    var showCards = true
    var showAnomaly = true
    var heatmapOn = false
    var heatmapBusy = false
    var immersiveOpen = false
    var forkId: String?
    var status = "Ready"
    var lastWhatIf: String?
    var callCount = 0

    @ObservationIgnored var store: StoreBuilder.Built?
    @ObservationIgnored let vizRoot = Entity()
    @ObservationIgnored var arcs = ArcLayer()
    @ObservationIgnored var ghosts = GhostLayer()
    @ObservationIgnored var heatmap = HeatmapLayer()

    var token: String {
        get { Keychain.get("proxyToken") ?? "" }
        set { Keychain.set(newValue, for: "proxyToken") }
    }

    var predictor: RoutedPredictor {
        let live = URL(string: proxyURL).flatMap { $0.scheme?.hasPrefix("http") == true ? BehaviorGPTPredictor(endpoint: $0, token: token) : nil }
        return RoutedPredictor(mode: mode, live: live)
    }

    func product(_ id: String) -> Product? { catalog.first { $0.id == id } }
    func shopper(_ id: String) -> ShopperAgent? { shoppers.first { $0.id == id } }

    // MARK: Scene

    func buildScene(into content: RealityViewContent) async -> Entity {
        let built = await StoreBuilder.build(catalog: catalog)
        store = built
        built.root.addChild(vizRoot)
        vizRoot.addChild(arcs.root)
        vizRoot.addChild(ghosts.root)
        vizRoot.addChild(heatmap.root)
        content.add(built.root)
        await spawnShoppers()
        return built.root
    }

    func spawnShoppers() async {
        shoppers.forEach { $0.root.removeFromParent() }
        shoppers = Persona.all.enumerated().map { ShopperAgent(persona: $1, index: $0) }
        for s in shoppers {
            store?.root.addChild(s.root)
            await s.loadBody()
            request(s)
        }
    }

    func reset() {
        catalog = Catalog.laidOut()
        for p in catalog { store?.slots[p.id]?.position = p.anchor - SIMD3(0, 0.12, 0) }
        refreshSaleSigns()
        forkId = nil
        ghosts.clear()
        lastWhatIf = nil
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
        ghosts.tick(dt)
        if showCards { arcs.follow(shoppers) }
    }

    func request(_ s: ShopperAgent) {
        s.phase = .thinking
        s.requestId += 1
        let rid = s.requestId
        let req = PredictionRequest(personaId: s.persona.id, history: s.history, cart: s.cart, catalog: catalog)
        let pred = predictor
        callCount += 1
        Task {
            let result: PredictionResult
            do { result = try await pred.predict(req) } catch {
                result = HeuristicPredictor().rank(req, from: nil)
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
        if forkId == s.id { ghosts.spawn(for: s, catalog: catalog) }
        guard !s.frozen else { return }
        execute(s)
    }

    func execute(_ s: ShopperAgent) {
        guard let choice = s.choose() else { return }
        s.target = choice
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
        catalog[i].onSale.toggle()
        lastWhatIf = (catalog[i].onSale ? "Sale on " : "Sale off ") + catalog[i].name
        refreshSaleSigns()
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
