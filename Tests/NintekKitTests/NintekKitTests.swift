import XCTest
@testable import NintekKit

/// Captures the request it's handed and returns a canned response, so the whole
/// APIClient path runs without a network. `@unchecked Sendable` is fine: tests
/// drive it serially.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var lastRequest: URLRequest?
    var status: Int = 200
    var body: Data = Data()
    var throwError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let throwError { throw throwError }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }
}

final class NintekKitTests: XCTestCase {

    private func makeAPI(transport: MockTransport, token: String? = "test-token") -> CairnAPI {
        CairnAPI(
            baseURL: CairnAPI.productionBaseURL,
            tokenProvider: StaticTokenProvider(token),
            transport: transport
        )
    }

    // MARK: Request construction

    func testRequestResolvesAgainstBaseURLAndAttachesBearer() async throws {
        let transport = MockTransport()
        transport.body = Data("[]".utf8)
        let api = makeAPI(transport: transport)

        _ = try await api.attempts()

        let req = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(req.url?.absoluteString,
                       "https://app-cairn-prod-lwxhu7jxlrbtu.azurewebsites.net/api/exam-prep/attempts")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func testNoTokenOmitsAuthorizationHeader() async throws {
        let transport = MockTransport()
        transport.body = Data("[]".utf8)
        let api = makeAPI(transport: transport, token: nil)

        _ = try await api.progress()

        let req = try XCTUnwrap(transport.lastRequest)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: Decoding real server shapes

    func testDecodesAttemptsList() async throws {
        let json = """
        [{"id":7,"mode":"full","score":82,"totalQuestions":50,"correctCount":41,
          "domain1Score":20,"domain1Total":25,"domain2Score":21,"domain2Total":25,
          "passed":1,"timeSpentSec":3120,"completedAt":"2026-07-17 14:05:00"}]
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let attempts = try await api.attempts()

        XCTAssertEqual(attempts.count, 1)
        let a = try XCTUnwrap(attempts.first)
        XCTAssertEqual(a.id, 7)
        XCTAssertEqual(a.score, 82)
        XCTAssertEqual(a.correctCount, 41)
        XCTAssertTrue(a.isPassed)
        XCTAssertEqual(a.timeSpentSec, 3120)
    }

    func testDecodesAttemptWithNullTimeSpent() async throws {
        let json = """
        {"id":9,"mode":"practice","score":60,"totalQuestions":10,"correctCount":6,
         "domain1Score":3,"domain1Total":5,"domain2Score":3,"domain2Total":5,
         "passed":0,"timeSpentSec":null,"completedAt":"2026-07-16 09:00:00",
         "results":[{"questionId":"q1","selected":"B","correct":1},
                    {"questionId":"q2","selected":"A","correct":0}]}
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let detail = try await api.attempt(id: 9)

        XCTAssertNil(detail.timeSpentSec)
        XCTAssertFalse(detail.isPassed)
        XCTAssertEqual(detail.results.count, 2)
        XCTAssertTrue(detail.results[0].isCorrect)
        XCTAssertFalse(detail.results[1].isCorrect)
    }

    func testDecodesProgressRows() async throws {
        let json = """
        [{"storageKey":"exam-prep-drill-stats:PL300","data":"{\\"x\\":1}","updatedAt":1752760000000}]
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let rows = try await api.progress()

        XCTAssertEqual(rows.first?.storageKey, "exam-prep-drill-stats:PL300")
        XCTAssertEqual(rows.first?.updatedAt, 1752760000000)
    }

    // MARK: Writes

    func testPutProgressSendsKeyAndDataBody() async throws {
        let transport = MockTransport()
        transport.body = Data("{\"success\":true}".utf8)
        let api = makeAPI(transport: transport)

        try await api.putProgress(key: "exam-prep-foo", data: "{\"a\":1}")

        let req = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(sent?["key"], "exam-prep-foo")
        XCTAssertEqual(sent?["data"], "{\"a\":1}")
    }

    func testDeleteProgressPercentEncodesKey() async throws {
        let transport = MockTransport()
        transport.body = Data("{\"success\":true}".utf8)
        let api = makeAPI(transport: transport)

        try await api.deleteProgress(key: "exam-prep-drill-stats:PL300")

        let req = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertTrue(req.url?.absoluteString.hasSuffix("exam-prep-drill-stats%3APL300") ?? false,
                      "colon should be percent-encoded, got \(req.url?.absoluteString ?? "nil")")
    }

    // MARK: Error mapping

    func testUnauthorizedMapsToAPIError() async throws {
        let transport = MockTransport()
        transport.status = 401
        transport.body = Data("{\"error\":\"Missing bearer token\"}".utf8)
        let api = makeAPI(transport: transport)

        do {
            _ = try await api.attempts()
            XCTFail("expected unauthorized")
        } catch let error as APIError {
            XCTAssertTrue(error.isUnauthorized)
        }
    }

    func testServerErrorSurfacesMessage() async throws {
        let transport = MockTransport()
        transport.status = 500
        transport.body = Data("{\"error\":\"boom\"}".utf8)
        let api = makeAPI(transport: transport)

        do {
            _ = try await api.attempts()
            XCTFail("expected http error")
        } catch let APIError.http(status, message) {
            XCTAssertEqual(status, 500)
            XCTAssertEqual(message, "boom")
        }
    }
}
