import Foundation

/// Errors surfaced by ``APIClient``. `unauthorized` is separated out so the app
/// can react to it specifically (e.g. bounce to sign-in) rather than treating
/// every non-2xx the same.
public enum APIError: Error, Equatable, Sendable {
    /// The request completed but the status code was outside 200–299.
    case http(status: Int, message: String?)
    /// 401 — token missing, expired, or rejected by the backend.
    case unauthorized
    /// The response body could not be decoded into the expected type.
    case decoding(String)
    /// A transport-level failure (offline, DNS, TLS, timeout).
    case transport(String)

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .http(let status, let message):
            return message.map { "Server error \(status): \($0)" } ?? "Server error \(status)."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .decoding(let detail):
            return "Unexpected response from the server. (\(detail))"
        case .transport(let detail):
            return "Couldn't reach the server. (\(detail))"
        }
    }
}
