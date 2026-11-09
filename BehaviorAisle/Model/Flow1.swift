import Foundation
import Observation
import RealityKit
import HumanCore
import HumanKit

/// Demo Flow 1: @handle -> HumanHD shopper + shopping preferences inside a 20 s budget.
/// Lanes run as separate proxy calls: fetch first, then body (vision) and shop (text) in parallel,
/// then HumanHD build as soon as the body lands. Each lane falls back locally so the flow always completes.
@MainActor
@Observable
final class Flow1 {
    enum LaneID: Int, CaseIterable, Identifiable {
        case fetch, body, shop, human, spawn
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .fetch: "X profile"
            case .body: "Photo → body"
            case .shop: "Posts → shopping"
            case .human: "HumanHD build"
            case .spawn: "Into the store"
            }
        }
        var route: String {
            switch self {
            case .fetch: "GET /twitter"
            case .body: "POST /classify/body"
            case .shop: "POST /classify/shop"
            case .human: "Human.make"
            case .spawn: "spawnImported"
            }
        }
        var icon: String {
            switch self {
            case .fetch: "at"
            case .body: "person.crop.square.badge.camera"
            case .shop: "text.magnifyingglass"
            case .human: "figure.stand"
            case .spawn: "cart"
            }
        }
    }

    enum State: Equatable { case waiting, running, done, fallback, failed }

    struct Lane: Equatable {
        var state: State = .waiting
        var start: Date?
        var end: Date?
        var detail = ""
    }

    static let budget: TimeInterval = 20

    var lanes: [LaneID: Lane] = [:]
    var started: Date?
    var finished: Date?
    var handle = ""
    var profile: TwitterProfile?
    var body: ProfileTraits.Body?
    var shop: ShopTraits?
    var traits: ProfileTraits?
    /// HumanHD preview for the window's turntable. Rebuilt per run.
    var preview: Entity?
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    var running: Bool { started != nil && finished == nil }
    var elapsed: TimeInterval { (finished ?? .now).timeIntervalSince(started ?? .now) }
    func lane(_ id: LaneID) -> Lane { lanes[id] ?? Lane() }

    func cancel() { task?.cancel(); task = nil }

    func run(_ input: String, model: AppModel) {
        let h = ProfileClient.normalize(input)
        guard !h.isEmpty else { error = "Enter an X handle"; return }
        cancel()
        handle = h
        lanes = [:]
        profile = nil; body = nil; shop = nil; traits = nil; preview = nil; error = nil
        started = .now
        finished = nil
        let cat = model.catalog
        guard let client = ProfileClient(predictURL: model.proxyURL, token: model.token) else {
            error = ProfileError.noProxy.localizedDescription
            finished = .now
            return
        }
        task = Task {
            defer { if finished == nil { finished = .now } }
            begin(.fetch)
            let p: TwitterProfile
            do { p = try await client.profile(h) } catch {
                end(.fetch, .failed, error.localizedDescription)
                self.error = error.localizedDescription
                return
            }
            guard !Task.isCancelled else { return }
            profile = p
            end(.fetch, .done, "\(p.tweets.count) posts · \(p.followers.map(Self.compact) ?? "–") followers")

            let seed = p.handle.lowercased().utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 } | 1
            async let bodyLane: Void = runBody(client, p, seed: seed)
            async let shopLane: Void = runShop(client, p, cat)
            _ = await (bodyLane, shopLane)
            guard !Task.isCancelled, let b = body, let s = shop else { return }

            let t = ProfileTraits(body: b, shop: s)
            traits = t
            model.importedProfile = p
            model.importedTraits = t
            begin(.spawn)
            let inStore = model.store != nil
            await model.spawnImported(p, t)
            end(.spawn, .done, inStore
                ? "heading to \(model.product(s.wishlist.first ?? "")?.name ?? "the shelves")"
                : "joins when the store opens")
            model.importStage = .done
        }
    }

    private func runBody(_ client: ProfileClient, _ p: TwitterProfile, seed: UInt64) async {
        begin(.body)
        var b: ProfileTraits.Body
        do {
            b = try await client.body(avatarURL: p.avatarUrl)
            end(.body, .done, b.confidence > 0.2 ? "confidence \(Int(b.confidence * 100))%" : "no face found, seeded body")
        } catch {
            b = .neutral
            end(.body, .fallback, "seeded body · \(Self.short(error))")
        }
        body = b
        begin(.human)
        let spec = b.confidence > 0.2 ? HumanTraitsMapper.spec(b, seed: seed) : HumanSpec.random(seed: seed)
        do {
            let c = try await Human.make(spec, seed: seed)
            preview = c.entity
            end(.human, .done, "\(b.hairStyle) hair · \(b.outfit)")
        } catch {
            end(.human, .failed, Self.short(error))
        }
    }

    private func runShop(_ client: ProfileClient, _ p: TwitterProfile, _ cat: [Product]) async {
        begin(.shop)
        do {
            var s = try await client.shop(p, catalog: cat)
            if s.wishlist.isEmpty { s.wishlist = ProfileTraits.heuristic(p, catalog: cat).wishlist }
            shop = s
            end(.shop, .done, "\(s.wishlist.count) items · \(s.interests.count) interests")
        } catch {
            shop = ProfileTraits.heuristic(p, catalog: cat).shop
            end(.shop, .fallback, "keyword match · \(Self.short(error))")
        }
    }

    private func begin(_ id: LaneID) { lanes[id] = Lane(state: .running, start: .now) }

    private func end(_ id: LaneID, _ s: State, _ detail: String) {
        var l = lane(id)
        l.state = s
        l.end = .now
        l.detail = detail
        lanes[id] = l
    }

    static func short(_ e: Error) -> String { String(e.localizedDescription.prefix(48)) }

    static func compact(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? String(format: "%.1fK", Double(n) / 1e3) : "\(n)"
    }
}
