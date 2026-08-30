import Foundation
import XCTest
@testable import NintekKit

final class BambuAPITests: XCTestCase {
    func testProviderConnectionsUsesCollectionGET() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.providerConnectionsJSON)
        let api = makeAPI(transport: transport)

        let response = try await api.providerConnections()

        XCTAssertEqual(response.thingiverse.source, .server)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/provider-connections")
        XCTAssertNil(request.httpBody)
    }

    func testSaveThingiverseTokenUsesExpectedPUTBody() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.thingiverseStatusJSON)
        let api = makeAPI(transport: transport)

        let status = try await api.saveThingiverseToken("write-only-secret")

        XCTAssertTrue(status.connected)
        XCTAssertEqual(status.source, .account)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/provider-connections/thingiverse")
        let body = try jsonBody(request)
        XCTAssertEqual(body["token"] as? String, "write-only-secret")
        XCTAssertEqual(Set(body.keys), ["token"])
    }

    func testDeleteThingiverseTokenUsesExpectedDELETEPath() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.disconnectedThingiverseStatusJSON)
        let api = makeAPI(transport: transport)

        let status = try await api.deleteThingiverseToken()

        XCTAssertFalse(status.connected)
        XCTAssertEqual(status.source, .none)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/provider-connections/thingiverse")
        XCTAssertNil(request.httpBody)
    }

    func testListBambuProjectsUsesCollectionGET() async throws {
        let transport = BambuRecordingTransport(responseJSON: "[]")
        let api = makeAPI(transport: transport)

        let projects = try await api.listBambuProjects()

        XCTAssertTrue(projects.isEmpty)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects")
        XCTAssertNil(request.httpBody)
    }

    func testBambuProjectUsesDetailGET() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.projectJSON)
        let api = makeAPI(transport: transport)

        let project = try await api.bambuProject(id: 42)

        XCTAssertEqual(project.id, 42)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects/42")
        XCTAssertNil(request.httpBody)
    }

    func testAnalyzeBambuURLUsesExpectedPOSTBody() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.analysisJSON)
        let api = makeAPI(transport: transport)
        let sourceURL = "https://www.thingiverse.com/thing:123"

        let analysis = try await api.analyzeBambuURL(sourceURL)

        XCTAssertEqual(analysis.sourceSite, .thingiverse)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects/analyze-url")
        XCTAssertEqual(try jsonBody(request)["url"] as? String, sourceURL)
    }

    func testCreateBambuProjectUsesSnakeCasePOSTBody() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.importJSON)
        let api = makeAPI(transport: transport)
        let input = BambuProjectInput(
            title: "Clamp",
            sourceUrl: "https://www.thingiverse.com/thing:123",
            description: "Printable clamp",
            creatorName: "Builder",
            licenseName: "CC BY"
        )

        let result = try await api.createBambuProject(input)

        XCTAssertEqual(result.project.id, 42)
        XCTAssertEqual(result.warnings, ["preview.jpg was blocked"])
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects")
        let body = try jsonBody(request)
        XCTAssertEqual(body["title"] as? String, "Clamp")
        XCTAssertEqual(body["source_url"] as? String, "https://www.thingiverse.com/thing:123")
        XCTAssertEqual(body["creator_name"] as? String, "Builder")
        XCTAssertEqual(body["license_name"] as? String, "CC BY")
        XCTAssertNil(body["sourceUrl"])
    }

    func testUpdateBambuProjectUsesSnakeCasePUTBody() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.projectJSON)
        let api = makeAPI(transport: transport)
        let input = BambuProjectInput(
            title: "Updated Clamp",
            sourceUrl: "https://www.thingiverse.com/thing:123",
            description: nil,
            creatorName: nil,
            licenseName: "MIT"
        )

        let project = try await api.updateBambuProject(id: 42, input)

        XCTAssertEqual(project.id, 42)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects/42")
        let body = try jsonBody(request)
        XCTAssertEqual(body["source_url"] as? String, "https://www.thingiverse.com/thing:123")
        XCTAssertEqual(body["license_name"] as? String, "MIT")
        XCTAssertNil(body["description"])
        XCTAssertNil(body["creator_name"])
    }

    func testDeleteBambuProjectUsesDetailDELETE() async throws {
        let transport = BambuRecordingTransport(statusCode: 204)
        let api = makeAPI(transport: transport)

        try await api.deleteBambuProject(id: 42)

        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects/42")
        XCTAssertNil(request.httpBody)
    }

    func testBambuAssetURLUsesEncodedUserKeyQuery() throws {
        let api = makeAPI(transport: BambuRecordingTransport())
        let userKey = "user key+and&more"

        let url = api.bambuAssetURL(assetId: 91, userKey: userKey)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/api/bambu-assets/91/image")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "oid", value: userKey)])
        XCTAssertTrue(try XCTUnwrap(components.percentEncodedQuery).contains("%20"))
        XCTAssertTrue(try XCTUnwrap(components.percentEncodedQuery).contains("%26"))
    }

    func testDownloadBambuAssetUsesAuthenticatedGETAndReplacesDestination() async throws {
        let downloadTransport = BambuDownloadTransport(data: Data("new-model".utf8))
        let api = makeAPI(
            transport: BambuRecordingTransport(),
            downloadTransport: downloadTransport
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let destinationURL = directoryURL.appendingPathComponent("model.3mf")
        try Data("old-model".utf8).write(to: destinationURL)

        try await api.downloadBambuAsset(id: 91, to: destinationURL)

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new-model".utf8))
        let captured = await downloadTransport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/bambu-assets/91")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "*/*")
    }

    func testDownloadBambuAssetPreservesCancellation() async throws {
        let api = makeAPI(
            transport: BambuRecordingTransport(),
            downloadTransport: CancelledBambuDownloadTransport()
        )
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try await api.downloadBambuAsset(id: 91, to: destinationURL)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        }
    }

    func testDownloadBambuAssetRejectsHTTPErrorWithoutReplacingDestination() async throws {
        let downloadTransport = BambuDownloadTransport(
            data: Data("error-response".utf8),
            statusCode: 403
        )
        let api = makeAPI(
            transport: BambuRecordingTransport(),
            downloadTransport: downloadTransport
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let destinationURL = directoryURL.appendingPathComponent("model.3mf")
        let originalData = Data("existing-model".utf8)
        try originalData.write(to: destinationURL)

        do {
            try await api.downloadBambuAsset(id: 91, to: destinationURL)
            XCTFail("Expected HTTP error")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 403, message: nil))
            XCTAssertEqual(try Data(contentsOf: destinationURL), originalData)
        }
    }

    func testUploadBambuAssetUsesMultipartProjectRoute() async throws {
        let transport = BambuRecordingTransport(responseJSON: Self.assetJSON)
        let api = makeAPI(transport: transport)
        let file = MultipartFile(
            filename: "clamp.3mf",
            mimeType: "application/vnd.ms-package.3dmanufacturing-3dmodel+xml",
            data: Data("mesh-data".utf8)
        )

        let asset = try await api.uploadBambuAsset(bambuProjectId: 42, file: file)

        XCTAssertEqual(asset.id, 91)
        XCTAssertEqual(asset.kind, .model)
        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects/42/assets")
        XCTAssertTrue(
            try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
                .hasPrefix("multipart/form-data; boundary=")
        )
        let body = try XCTUnwrap(request.httpBody)
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(bodyText.contains(#"name="file"; filename="clamp.3mf""#))
        XCTAssertTrue(bodyText.contains("Content-Type: application/vnd.ms-package.3dmanufacturing-3dmodel+xml"))
        XCTAssertTrue(bodyText.contains("mesh-data"))
    }

    func testUploadBambuAssetFileUsesAuthenticatedFileBackedMultipartAndCleansUp() async throws {
        let fileUploadTransport = BambuFileUploadTransport(responseJSON: Self.assetJSON)
        let api = makeAPI(
            transport: BambuRecordingTransport(),
            fileUploadTransport: fileUploadTransport
        )
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let sourceURL = directoryURL.appendingPathComponent("source.3mf")
        var sourceData = Data(repeating: 0x41, count: 1_048_576)
        sourceData.append(Data("second-chunk-tail".utf8))
        try sourceData.write(to: sourceURL)

        let asset = try await api.uploadBambuAssetFile(
            bambuProjectId: 42,
            sourceFileURL: sourceURL,
            filename: #"clamp "final".3mf"#,
            mimeType: "application/vnd.ms-package.3dmanufacturing-3dmodel+xml",
            onProgress: { _ in }
        )

        XCTAssertEqual(asset.id, 91)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        let capturedResult = await fileUploadTransport.capture()
        let captured = try XCTUnwrap(capturedResult)
        let request = captured.request
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/bambu-projects/42/assets")
        let authorizationParts = try XCTUnwrap(
            request.value(forHTTPHeaderField: "Authorization")
        ).split(separator: " ")
        XCTAssertEqual(authorizationParts, ["Bearer", "test-token"])
        XCTAssertNil(request.httpBody)
        XCTAssertTrue(
            try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
                .hasPrefix("multipart/form-data; boundary=")
        )
        let bodyText = try XCTUnwrap(String(data: captured.body, encoding: .utf8))
        XCTAssertTrue(bodyText.contains(#"name="file"; filename="clamp \"final\".3mf""#))
        XCTAssertTrue(bodyText.contains("Content-Type: application/vnd.ms-package.3dmanufacturing-3dmodel+xml"))
        XCTAssertTrue(bodyText.contains("second-chunk-tail"))
        XCTAssertTrue(captured.hadProgressHandler)
        XCTAssertFalse(FileManager.default.fileExists(atPath: captured.multipartURL.path))
    }

    func testUploadBambuAssetFilePreservesCancellationAndCleansUp() async throws {
        let fileUploadTransport = CancelledBambuFileUploadTransport()
        let api = makeAPI(
            transport: BambuRecordingTransport(),
            fileUploadTransport: fileUploadTransport
        )
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("model-bytes".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        do {
            _ = try await api.uploadBambuAssetFile(
                bambuProjectId: 42,
                sourceFileURL: sourceURL,
                filename: "model.stl",
                mimeType: "model/stl"
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let capturedURL = await fileUploadTransport.multipartURL()
            let multipartURL = try XCTUnwrap(capturedURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: multipartURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        }
    }

    func testUploadBambuAssetFileRejectsCRLFInFilenameBeforeUpload() async throws {
        let fileUploadTransport = BambuFileUploadTransport(responseJSON: Self.assetJSON)
        let api = makeAPI(
            transport: BambuRecordingTransport(),
            fileUploadTransport: fileUploadTransport
        )
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("model-bytes".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        do {
            _ = try await api.uploadBambuAssetFile(
                bambuProjectId: 42,
                sourceFileURL: sourceURL,
                filename: "model.3mf\r\nX-Injected: true",
                mimeType: "model/3mf"
            )
            XCTFail("Expected invalid multipart filename")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("filename"))
            let capture = await fileUploadTransport.capture()
            XCTAssertNil(capture)
        }
    }

    func testDeleteBambuAssetUsesAssetDELETEPath() async throws {
        let transport = BambuRecordingTransport(statusCode: 204)
        let api = makeAPI(transport: transport)

        try await api.deleteBambuAsset(id: 91)

        let captured = await transport.lastRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/bambu-assets/91")
        XCTAssertNil(request.httpBody)
    }

    private func makeAPI(
        transport: BambuRecordingTransport,
        downloadTransport: HTTPDownloadTransport = URLSession.shared,
        fileUploadTransport: HTTPFileUploadTransport = URLSession.shared
    ) -> WorkshopAPI {
        WorkshopAPI(
            baseURL: URL(string: "https://workshop.example")!,
            tokenProvider: StaticTokenProvider("test-token"),
            transport: transport,
            downloadTransport: downloadTransport,
            fileUploadTransport: fileUploadTransport
        )
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let projectJSON = """
    {"id":42,"title":"Clamp","source_url":"https://www.thingiverse.com/thing:123",
     "source_site":"thingiverse","source_model_id":"123","description":"Printable clamp",
     "creator_name":"Builder","license_name":"CC BY","hero_asset_id":null,
     "created_at":"2026-08-29","updated_at":"2026-08-30"}
    """

    private static let providerConnectionsJSON = """
    {"thingiverse":{"connected":true,"source":"server","storage_configured":true}}
    """

    private static let thingiverseStatusJSON = """
    {"connected":true,"source":"account","storage_configured":true}
    """

    private static let disconnectedThingiverseStatusJSON = """
    {"connected":false,"source":"none","storage_configured":true}
    """

    private static let assetJSON = """
    {"id":91,"bambu_project_id":42,"kind":"model","filename":"clamp.3mf",
     "content_type":"application/vnd.ms-package.3dmanufacturing-3dmodel+xml",
     "size_bytes":9,"original_url":"manual://clamp.3mf","sort_order":0}
    """

    private static let analysisJSON = """
    {"source_site":"thingiverse","source_model_id":"123","title":"Clamp",
     "description":"Printable clamp","creator_name":"Builder","license_name":"CC BY",
     "preview_image_url":"https://img.example/clamp.jpg","image_count":1,"file_count":1,
     "files":[{"filename":"clamp.stl","kind":"model"}]}
    """

    private static let importJSON = """
    {"project":{"id":42,"title":"Clamp","source_url":"https://www.thingiverse.com/thing:123",
                "source_site":"thingiverse","source_model_id":"123","description":"Printable clamp",
                "creator_name":"Builder","license_name":"CC BY","hero_asset_id":null,
                "created_at":"2026-08-29","updated_at":"2026-08-30"},
     "warnings":["preview.jpg was blocked"]}
    """
}

private actor BambuRecordingTransport: HTTPTransport {
    private let responseData: Data
    private let statusCode: Int
    private var request: URLRequest?

    init(responseJSON: String = "", statusCode: Int = 200) {
        responseData = Data(responseJSON.utf8)
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func lastRequest() -> URLRequest? {
        request
    }
}

private actor BambuDownloadTransport: HTTPDownloadTransport {
    private let data: Data
    private let statusCode: Int
    private var request: URLRequest?

    init(data: Data, statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func downloadFile(for request: URLRequest) async throws -> (URL, URLResponse) {
        self.request = request
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: temporaryURL, options: .atomic)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (temporaryURL, response)
    }

    func lastRequest() -> URLRequest? {
        request
    }
}

private struct CancelledBambuDownloadTransport: HTTPDownloadTransport {
    func downloadFile(for request: URLRequest) async throws -> (URL, URLResponse) {
        throw URLError(.cancelled)
    }
}

private actor BambuFileUploadTransport: HTTPFileUploadTransport {
    struct Capture: Sendable {
        let request: URLRequest
        let multipartURL: URL
        let body: Data
        let hadProgressHandler: Bool
    }

    private let responseData: Data
    private var capturedRequest: URLRequest?
    private var multipartURL: URL?
    private var body = Data()
    private var hadProgressHandler = false

    init(responseJSON: String) {
        responseData = Data(responseJSON.utf8)
    }

    func uploadFile(
        for request: URLRequest,
        fromFile fileURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (Data, URLResponse) {
        capturedRequest = request
        multipartURL = fileURL
        body = try Data(contentsOf: fileURL)
        hadProgressHandler = onProgress != nil
        onProgress?(1)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func capture() -> Capture? {
        guard let capturedRequest, let multipartURL else { return nil }
        return Capture(
            request: capturedRequest,
            multipartURL: multipartURL,
            body: body,
            hadProgressHandler: hadProgressHandler
        )
    }
}

private actor CancelledBambuFileUploadTransport: HTTPFileUploadTransport {
    private var capturedMultipartURL: URL?

    func uploadFile(
        for request: URLRequest,
        fromFile fileURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (Data, URLResponse) {
        capturedMultipartURL = fileURL
        throw URLError(.cancelled)
    }

    func multipartURL() -> URL? {
        capturedMultipartURL
    }
}
