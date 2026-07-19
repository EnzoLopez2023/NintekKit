import Foundation

/// The transport seam under ``APIClient``. `URLSession` conforms to it in
/// production; tests inject a stub so the whole client is exercised without a
/// network. Mirrors the one `URLSession` method the client needs.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

/// Minimal async JSON client. Injects the bearer token from a ``TokenProvider``
/// on every request and maps failures onto ``APIError``. This is the exact
/// native counterpart of the web app's `apiFetch` wrapper — same base origin,
/// same `Authorization: Bearer` scheme against the same Azure backend.
public struct APIClient: Sendable {
    public let baseURL: URL
    private let tokenProvider: TokenProvider
    private let transport: HTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        baseURL: URL,
        tokenProvider: TokenProvider,
        transport: HTTPTransport = URLSession.shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.decoder = decoder
        self.encoder = encoder
    }

    // MARK: Requests

    public func get<Response: Decodable>(_ path: String, as type: Response.Type = Response.self) async throws -> Response {
        try await send(method: "GET", path: path, body: nil)
    }

    @discardableResult
    public func put<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, as type: Response.Type = Response.self
    ) async throws -> Response {
        try await send(method: "PUT", path: path, body: encoder.encode(body))
    }

    @discardableResult
    public func post<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, as type: Response.Type = Response.self
    ) async throws -> Response {
        try await send(method: "POST", path: path, body: encoder.encode(body))
    }

    @discardableResult
    public func delete<Response: Decodable>(_ path: String, as type: Response.Type = Response.self) async throws -> Response {
        try await send(method: "DELETE", path: path, body: nil)
    }

    /// DELETE with a JSON body (e.g. bulk operations that take `{ ids: [...] }`).
    @discardableResult
    public func deleteWithBody<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, as type: Response.Type = Response.self
    ) async throws -> Response {
        try await send(method: "DELETE", path: path, body: encoder.encode(body))
    }

    /// Fetch raw bytes (e.g. an image) with the bearer token attached. `path`
    /// may include a query string. No JSON decoding.
    public func getData(_ path: String) async throws -> Data {
        let token = try await tokenProvider.accessToken()
        let request = makeRequest(method: "GET", path: path, token: token, body: nil)
        let data: Data, response: URLResponse
        do { (data, response) = try await transport.data(for: request) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("Non-HTTP response.") }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.http(status: http.statusCode, message: nil)
        }
        return data
    }

    // MARK: Core

    /// Builds a request against `baseURL`, attaches the bearer token, performs
    /// it, and decodes the JSON body. Exposed `internal` so tests can assert on
    /// the exact `URLRequest` produced.
    func makeRequest(method: String, path: String, token: String?, body: Data?) -> URLRequest {
        // `path` is expected to be root-relative ("/api/…"); resolving against
        // baseURL preserves the host and scheme.
        let url = URL(string: path, relativeTo: baseURL) ?? baseURL
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<Response: Decodable>(method: String, path: String, body: Data?) async throws -> Response {
        let token = try await tokenProvider.accessToken()
        let request = makeRequest(method: method, path: path, token: token, body: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.http(status: http.statusCode, message: Self.serverMessage(from: data))
        }

        // Tolerate empty bodies decoded into `EmptyResponse`.
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Pulls `{ "error": "…" }` out of a failed response body when present.
    private static func serverMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let error: String }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    }
}

/// Decodable placeholder for endpoints whose body we don't need (e.g. the
/// `{ success: true }` responses from progress writes).
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}

/// Encodable placeholder for POST/PUT routes that take no meaningful body
/// (checkin, sold, restore) — encodes to `{}`.
public struct EmptyBody: Encodable, Sendable {
    public init() {}
}
