import Foundation

/// Proxy calls for the profile import. Keys (X bearer, OpenRouter) live in the proxy, never in the app.
/// `GET  <base>/twitter?handle=x`  -> TwitterProfile
/// `POST <base>/classify` {profile, catalog} -> ProfileTraits
struct ProfileClient: Sendable {
    var base: URL
    var token: String?

    /// Derives the proxy base from the predict endpoint (".../predict" -> "...").
    init?(predictURL: String, token: String?) {
        guard var c = URLComponents(string: predictURL), c.scheme?.hasPrefix("http") == true else { return nil }
        if c.path.hasSuffix("/predict") { c.path.removeLast("/predict".count) }
        guard let u = c.url else { return nil }
        base = u
        self.token = token
    }

    static func normalize(_ input: String) -> String {
        var h = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["https://", "http://", "www.", "x.com/", "twitter.com/", "@"] where h.lowercased().hasPrefix(p) {
            h.removeFirst(p.count)
        }
        return String(h.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
    }

    func profile(_ handle: String) async throws -> TwitterProfile {
        var c = URLComponents(url: base.appendingPathComponent("twitter"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "handle", value: handle)]
        return try await send(URLRequest(url: c.url!, timeoutInterval: 15))
    }

    func classify(_ profile: TwitterProfile, catalog: [Product]) async throws -> ProfileTraits {
        var r = URLRequest(url: base.appendingPathComponent("classify"), timeoutInterval: 45)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Item: Encodable { var id, name, category: String; var price: Double }
        struct Body: Encodable { var profile: TwitterProfile; var catalog: [Item] }
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        r.httpBody = try enc.encode(Body(profile: profile, catalog: catalog.map {
            Item(id: $0.id, name: $0.name, category: $0.category.rawValue, price: $0.price)
        }))
        var t: ProfileTraits = try await send(r)
        let known = Set(catalog.map(\.id))
        t.wishlist = t.wishlist.filter(known.contains)
        if t.wishlist.isEmpty { t.wishlist = ProfileTraits.heuristic(profile, catalog: catalog).wishlist }
        return t
    }

    /// Demo Flow 1 lane: avatar photo -> body traits (`POST /classify/body`).
    func body(avatarURL: String?) async throws -> ProfileTraits.Body {
        var r = URLRequest(url: base.appendingPathComponent("classify/body"), timeoutInterval: 16)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["avatar_url": avatarURL.map { $0 as Any } ?? NSNull()])
        return try await send(r)
    }

    /// Demo Flow 1 lane: bio + posts + catalog -> shopping traits (`POST /classify/shop`).
    func shop(_ profile: TwitterProfile, catalog: [Product]) async throws -> ShopTraits {
        var r = URLRequest(url: base.appendingPathComponent("classify/shop"), timeoutInterval: 16)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Item: Encodable { var id, name, category: String; var price: Double }
        struct Body: Encodable { var profile: TwitterProfile; var catalog: [Item] }
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        r.httpBody = try enc.encode(Body(profile: profile, catalog: catalog.map {
            Item(id: $0.id, name: $0.name, category: $0.category.rawValue, price: $0.price)
        }))
        var t: ShopTraits = try await send(r)
        let known = Set(catalog.map(\.id))
        t.wishlist = t.wishlist.filter(known.contains)
        return t
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        var r = req
        if let token, !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ProfileError.server((resp as? HTTPURLResponse)?.statusCode ?? 0, String(msg.prefix(120)))
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }
}

enum ProfileError: LocalizedError {
    case server(Int, String)
    case noProxy
    var errorDescription: String? {
        switch self {
        case .server(let code, let m): "Proxy \(code): \(m)"
        case .noProxy: "Set the proxy URL first"
        }
    }
}
