import Foundation

/// Supplies a bearer access token for API requests. The app implements this by
/// wrapping MSAL (silent acquisition + redirect on interaction-required); tests
/// and previews use ``StaticTokenProvider``. Keeping auth behind a protocol is
/// what lets NintekKit stay free of the MSAL dependency.
public protocol TokenProvider: Sendable {
    /// Returns a valid access token, or `nil` when there is no signed-in user
    /// (e.g. anonymous/preview state). Throwing signals a real auth failure.
    func accessToken() async throws -> String?
}

/// A fixed-token provider for tests, SwiftUI previews, and manual dev builds
/// where you paste a token instead of wiring MSAL.
public struct StaticTokenProvider: TokenProvider {
    private let token: String?

    public init(_ token: String?) {
        self.token = token
    }

    public func accessToken() async throws -> String? {
        token
    }
}
