import Foundation
import XCTest
@testable import NintekKit

final class WorkshopAPITests: XCTestCase {
    func testDeleteAccountUsesAuthenticatedCurrentUserRoute() async throws {
        let transport = RecordingTransport()
        let api = WorkshopAPI(
            baseURL: URL(string: "https://workshop.example")!,
            tokenProvider: StaticTokenProvider("test-token"),
            transport: transport
        )

        try await api.deleteAccount()

        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "https://workshop.example/api/account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNil(request.httpBody)
    }
}

private actor RecordingTransport: HTTPTransport {
    private var request: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }

    func lastRequest() -> URLRequest? {
        request
    }
}
