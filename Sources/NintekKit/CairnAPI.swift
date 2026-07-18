import Foundation

/// Typed wrapper over the Cairn exam-prep endpoints. Thin by design — it maps
/// each REST route to one async method and leaves policy (caching, retry,
/// offline queueing) to the app. The base origin is the same Azure App Service
/// the web app talks to.
public struct CairnAPI: Sendable {
    private let client: APIClient

    /// Production Cairn backend — the same origin the web build resolves to.
    public static let productionBaseURL = URL(string: "https://app-cairn-prod-lwxhu7jxlrbtu.azurewebsites.net")!

    public init(client: APIClient) {
        self.client = client
    }

    public init(baseURL: URL = CairnAPI.productionBaseURL, tokenProvider: TokenProvider, transport: HTTPTransport = URLSession.shared) {
        self.client = APIClient(baseURL: baseURL, tokenProvider: tokenProvider, transport: transport)
    }

    // MARK: Attempts

    /// Most recent exam attempts (server caps at 50, newest first).
    public func attempts() async throws -> [ExamAttempt] {
        try await client.get("/api/exam-prep/attempts")
    }

    /// A single attempt with its per-question results.
    public func attempt(id: Int) async throws -> AttemptDetail {
        try await client.get("/api/exam-prep/attempts/\(id)")
    }

    // MARK: Progress (synced key-value store)

    /// Every `exam-prep-*` progress row for the signed-in user.
    public func progress() async throws -> [ProgressEntry] {
        try await client.get("/api/exam-prep/progress")
    }

    /// Upsert one progress key. `data` is an already-serialized string, exactly
    /// as the web app stores it in localStorage.
    public func putProgress(key: String, data: String) async throws {
        struct Body: Encodable { let key: String; let data: String }
        try await client.put("/api/exam-prep/progress", body: Body(key: key, data: data), as: EmptyResponse.self)
    }

    /// Delete one progress key.
    public func deleteProgress(key: String) async throws {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        try await client.delete("/api/exam-prep/progress/\(encoded)", as: EmptyResponse.self)
    }
}
