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

    @discardableResult
    public func patch<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, as type: Response.Type = Response.self
    ) async throws -> Response {
        try await send(method: "PATCH", path: path, body: encoder.encode(body))
    }

    /// POST a pre-encoded JSON body verbatim (bypasses the shared encoder — used
    /// for endpoints whose keys don't follow the client's casing convention).
    @discardableResult
    public func postRawJSON<Response: Decodable>(_ path: String, jsonBody: Data, as type: Response.Type = Response.self) async throws -> Response {
        try await send(method: "POST", path: path, body: jsonBody)
    }

    /// PUT a pre-encoded JSON body verbatim (camelCase-preserving counterpart of
    /// `postRawJSON` — used for Workshop's cut-plan-config, whose keys are
    /// camelCase and must round-trip unchanged with the web app).
    @discardableResult
    public func putRawJSON<Response: Decodable>(_ path: String, jsonBody: Data, as type: Response.Type = Response.self) async throws -> Response {
        try await send(method: "PUT", path: path, body: jsonBody)
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

    // MARK: Multipart

    /// POST a `multipart/form-data` body — text `fields` plus an optional binary
    /// `file` part. Used for Workshop's image and build-log uploads (the web app
    /// sends `FormData`, not base64 JSON). Attaches the bearer token and decodes
    /// the JSON response like `send`. Added for Workshop; ShopKeep's routes are
    /// untouched.
    ///
    /// When `onProgress` is supplied, the upload runs on a dedicated `URLSession`
    /// with a delegate that reports fractional progress (`didSendBodyData`) —
    /// this is the one call that bypasses the injectable `transport` seam, since
    /// progress reporting is inherently tied to a real `URLSession` upload task.
    /// Omit `onProgress` (the default) to keep using `transport`, e.g. in tests.
    @discardableResult
    public func postMultipart<Response: Decodable>(
        _ path: String,
        fields: [String: String] = [:],
        file: MultipartFile? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let crlf = "\r\n"
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        for (name, value) in fields {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            append("\(value)\(crlf)")
        }
        if let file {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.filename)\"\(crlf)")
            append("Content-Type: \(file.mimeType)\(crlf)\(crlf)")
            body.append(file.data)
            append(crlf)
        }
        append("--\(boundary)--\(crlf)")

        let token = try await tokenProvider.accessToken()
        let url = URL(string: path, relativeTo: baseURL) ?? baseURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data, response: URLResponse
        do {
            if let onProgress {
                let delegate = UploadProgressDelegate(onProgress: onProgress)
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                defer { session.finishTasksAndInvalidate() }
                (data, response) = try await session.upload(for: request, from: body)
            } else {
                request.httpBody = body
                (data, response) = try await transport.data(for: request)
            }
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("Non-HTTP response.") }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.http(status: http.statusCode, message: Self.serverMessage(from: data))
        }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
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

/// Reports fractional upload progress (0...1) via `URLSessionTaskDelegate`, for
/// `APIClient.postMultipart`'s `onProgress` parameter.
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
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

/// One binary part for ``APIClient/postMultipart(_:fields:file:as:)``.
public struct MultipartFile: Sendable {
    public let fieldName: String
    public let filename: String
    public let mimeType: String
    public let data: Data

    /// - Parameters:
    ///   - fieldName: form field name (Workshop expects `"file"`).
    ///   - filename: original filename; its extension drives the server's MIME sniff.
    ///   - mimeType: content type of the bytes (e.g. `image/jpeg`, `application/pdf`).
    ///   - data: the raw bytes.
    public init(fieldName: String = "file", filename: String, mimeType: String, data: Data) {
        self.fieldName = fieldName; self.filename = filename; self.mimeType = mimeType; self.data = data
    }
}
