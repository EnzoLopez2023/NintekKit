import Foundation

/// Typed wrapper over the ShopKeep Express API (per-user SQLite behind Entra
/// JWT auth). Thin by design — one async method per route, sharing NintekKit's
/// `APIClient` (bearer-token transport). The server returns snake_case JSON, so
/// this configures the decoder with `.convertFromSnakeCase`.
public struct ShopKeepAPI: Sendable {
    private let client: APIClient

    /// Production ShopKeep backend (same origin the web app uses).
    public static let productionBaseURL = URL(string: "https://app-shopkeep-prod-lwxhu7jxlrbtu.azurewebsites.net")!

    public init(baseURL: URL = ShopKeepAPI.productionBaseURL,
                tokenProvider: TokenProvider,
                transport: HTTPTransport = URLSession.shared) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.client = APIClient(baseURL: baseURL, tokenProvider: tokenProvider,
                                transport: transport, decoder: decoder)
    }

    /// Backend origin — used to build authenticated image URLs.
    public var baseURL: URL { client.baseURL }

    // MARK: Dashboard

    public func stats() async throws -> DashboardStats {
        try await client.get("/api/stats")
    }

    public func categoryStats() async throws -> [CategoryCount] {
        try await client.get("/api/stats/categories")
    }

    public func recentTools(limit: Int = 5) async throws -> [Tool] {
        try await client.get("/api/tools/recent?limit=\(limit)")
    }

    public func alerts() async throws -> Alerts {
        try await client.get("/api/alerts")
    }

    // MARK: Inventory

    /// Filtered tool list. All filters optional; nil = no constraint.
    public func tools(search: String? = nil, category: String? = nil, brand: String? = nil,
                      status: String? = nil, condition: String? = nil,
                      storageLocation: String? = nil, subLocation: String? = nil) async throws -> [Tool] {
        var q: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            if let value, !value.isEmpty { q.append(URLQueryItem(name: name, value: value)) }
        }
        add("search", search); add("category", category); add("brand", brand)
        add("status", status); add("condition", condition)
        add("storage_location", storageLocation); add("sub_location", subLocation)

        var comps = URLComponents()
        comps.path = "/api/tools"
        comps.queryItems = q.isEmpty ? nil : q
        return try await client.get(comps.string ?? "/api/tools")
    }

    public func tool(id: Int) async throws -> Tool {
        try await client.get("/api/tools/\(id)")
    }

    // MARK: Images

    /// Authenticated URL for an image's bytes. Native must attach the bearer
    /// token as a header when loading it (the web `?oid=` param is not used).
    public func imageURL(_ image: ToolImage) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/tools/images/\(image.id)"),
                                  resolvingAgainstBaseURL: false)
        if let size = image.imageSize {
            comps?.queryItems = [URLQueryItem(name: "v", value: String(size))]
        }
        return comps?.url ?? baseURL
    }
}
