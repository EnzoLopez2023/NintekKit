import Foundation
import XCTest
@testable import NintekKit

final class ShopKeepAPITests: XCTestCase {
    func testImageDataUsesBearerProtectedPrivateMediaRoute() async throws {
        let transport = ShopKeepRecordingTransport()
        let api = makeAPI(transport: transport)
        let image = ToolImage(
            id: 42,
            imageName: "saw.jpg",
            imageType: "image/jpeg",
            imageSize: 12_345
        )

        _ = try await api.imageData(image)

        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://shopkeep.example/api/tools/images/42?media_v=12345"
        )
        assertBearerOnlyPrivateMediaRequest(request)
    }

    func testImageURLUsesStablePrivateMediaCacheVersion() {
        let api = makeAPI(transport: ShopKeepRecordingTransport())
        let image = ToolImage(
            id: 42,
            imageName: "saw.jpg",
            imageType: "image/jpeg",
            imageSize: 12_345
        )

        let url = api.imageURL(image)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        XCTAssertEqual(components?.path, "/api/tools/images/42")
        XCTAssertEqual(components?.queryItems, [URLQueryItem(name: "media_v", value: "12345")])
        XCTAssertFalse(components?.queryItems?.contains(where: { $0.name == "oid" }) ?? false)
    }

    func testDocumentDataUsesBearerProtectedPrivateMediaRoute() async throws {
        let transport = ShopKeepRecordingTransport()
        let api = makeAPI(transport: transport)
        let document = ToolDocument(
            id: 84,
            label: "manual",
            fileName: "manual.pdf",
            fileType: "application/pdf",
            uploadedAt: nil
        )

        _ = try await api.documentData(document)

        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://shopkeep.example/api/tools/documents/84")
        XCTAssertNil(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.query)
        assertBearerOnlyPrivateMediaRequest(request)
    }

    func testStreamedRawDownloadsUseNonpersistentReloadIgnoringConfiguration() {
        let configuration = APIClient.rawDataSessionConfiguration()

        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    private func makeAPI(transport: HTTPTransport) -> ShopKeepAPI {
        ShopKeepAPI(
            baseURL: URL(string: "https://shopkeep.example")!,
            tokenProvider: StaticTokenProvider("test-token"),
            transport: transport
        )
    }

    private func assertBearerOnlyPrivateMediaRequest(
        _ request: URLRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(request.httpMethod, "GET", file: file, line: line)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-token",
            file: file,
            line: line
        )
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, file: file, line: line)

        let queryItems = URLComponents(
            url: request.url!,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        XCTAssertFalse(queryItems.contains(where: { $0.name.lowercased() == "oid" }), file: file, line: line)

        let headerNames = request.allHTTPHeaderFields?.keys.map { $0.lowercased() } ?? []
        XCTAssertFalse(
            headerNames.contains(where: {
                $0.contains("oid") || $0.contains("identity") || $0.contains("user-id")
            }),
            file: file,
            line: line
        )
    }
}

private actor ShopKeepRecordingTransport: HTTPTransport {
    private var request: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data([0x01]), response)
    }

    func lastRequest() -> URLRequest? {
        request
    }
}
