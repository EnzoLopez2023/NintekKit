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

    // MARK: Content decoding

    func testDecodesCatalog() async throws {
        let json = """
        [{"id":"PL300","code":"PL-300","vendor":"Microsoft","title":"Power BI Data Analyst",
          "tagline":"Model, visualize, analyze.","status":"active","level":"Associate",
          "domains":[{"label":"Prepare the data","weight":"25–30%"}],
          "durationMin":100,"passScore":700,"questionCount":116},
         {"id":"AB900","code":"AB-900","vendor":"Microsoft","title":"Coming soon",
          "tagline":"tbd","status":"coming-soon"}]
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let exams = try await api.catalog()
        XCTAssertEqual(exams.count, 2)
        XCTAssertTrue(exams[0].isActive)
        XCTAssertEqual(exams[0].domains?.first?.weight, "25–30%")
        XCTAssertFalse(exams[1].isActive)
        XCTAssertNil(exams[1].domains)        // optional fields absent → nil
        XCTAssertNil(exams[1].questionCount)
    }

    func testDecodesFlashcards() async throws {
        let json = """
        [{"id":"pl300-fc-001","topic":"DAX","front":"Q?","back":"**A**"}]
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let cards = try await api.flashcards(examId: "PL300")
        XCTAssertEqual(cards.first?.topic, "DAX")
        XCTAssertEqual(cards.first?.back, "**A**")
    }

    func testDecodesQuestionWithUnknownTypeAndOptionalBlocks() async throws {
        // Unknown `type` must decode (→ .unknown), optional blocks absent → nil.
        let json = """
        [{"id":"q1","domain":1,"subdomain":"Storage modes","type":"single","difficulty":"easy",
          "question":"Which mode?","options":["A","B"],"correctAnswers":[1],
          "explanation":"because","examTip":"tip"},
         {"id":"q2","domain":2,"subdomain":"x","type":"drag-drop","difficulty":"hard",
          "question":"Q","options":[],"correctAnswers":[],"explanation":"e"}]
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let qs = try await api.questions(examId: "PL300")
        XCTAssertEqual(qs[0].kind, .single)
        XCTAssertEqual(qs[0].examTip, "tip")
        XCTAssertNil(qs[0].match)
        XCTAssertEqual(qs[1].kind, .unknown)  // future type doesn't break decoding
        XCTAssertEqual(qs[1].domain, 2)
    }

    // MARK: SM-2 flashcard engine

    func testSM2GotItProgressionMatchesWeb() {
        let key = FlashcardSM2.storageKey(examId: "PL300")
        XCTAssertEqual(key, "exam-prep-flashcard-stats:PL300")

        let t0 = 1_000_000_000_000
        // First "got-it": interval max(2, round(max(1,0)*3)) = 3; ease 0.5*1.15=0.575
        var stats = FlashcardSM2.record([:], cardId: "c1", rating: .gotIt, now: t0)
        XCTAssertEqual(stats["c1"]?.interval, 3)
        XCTAssertEqual(stats["c1"]?.reviews, 1)
        XCTAssertEqual(stats["c1"]?.ease ?? 0, 0.575, accuracy: 1e-9)
        XCTAssertEqual(stats["c1"]?.nextReviewAt, t0 + 3 * 86_400_000)

        // Second "got-it": interval max(2, round(3*3)) = 9
        stats = FlashcardSM2.record(stats, cardId: "c1", rating: .gotIt, now: t0)
        XCTAssertEqual(stats["c1"]?.interval, 9)
    }

    func testSM2ForgotResetsIntervalAndDropsEase() {
        let seeded: FlashcardStatsMap = ["c1": FlashcardStat(cardId: "c1", reviews: 5, interval: 30, ease: 0.8)]
        let stats = FlashcardSM2.record(seeded, cardId: "c1", rating: .forgot, now: 0)
        XCTAssertEqual(stats["c1"]?.interval, 1)
        XCTAssertEqual(stats["c1"]?.ease ?? 0, 0.56, accuracy: 1e-9)   // 0.8*0.7
    }

    func testSM2DueQueueExcludesNotYetDueAndSortsOverdueFirst() {
        struct Card: Identifiable { let id: String }
        let cards = [Card(id: "a"), Card(id: "b"), Card(id: "c")]
        let now = 1_000_000
        let stats: FlashcardStatsMap = [
            "a": FlashcardStat(cardId: "a", nextReviewAt: now + 100),   // future → excluded
            "b": FlashcardStat(cardId: "b", nextReviewAt: now - 500),   // overdue 500
            // c: never reviewed → most overdue (Int.max)
        ]
        let due = FlashcardSM2.dueQueue(cards, stats: stats, now: now).map(\.id)
        XCTAssertEqual(due, ["c", "b"])
    }

    func testFlashcardStatRoundTripsJSON() throws {
        let stat = FlashcardStat(cardId: "c1", reviews: 2, interval: 9, ease: 0.66, nextReviewAt: 123, lastReviewedAt: 45)
        let data = try JSONEncoder().encode(["c1": stat])
        let back = try JSONDecoder().decode(FlashcardStatsMap.self, from: data)
        XCTAssertEqual(back["c1"], stat)
    }

    func testDecodesStatsWithNullsWhenNoAttempts() async throws {
        let json = """
        {"totalAttempts":0,"passedAttempts":null,"bestScore":null,"avgScore":null,
         "avgTime":null,"weakAreas":[]}
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let stats = try await api.stats()
        XCTAssertFalse(stats.hasAttempts)
        XCTAssertNil(stats.bestScore)
        XCTAssertTrue(stats.weakAreas.isEmpty)
    }

    func testDecodesStatsWithWeakAreas() async throws {
        let json = """
        {"totalAttempts":3,"passedAttempts":1,"bestScore":780,"avgScore":690.5,"avgTime":2100.0,
         "weakAreas":[{"questionId":"pl300-sm-002","attempts":4,"wrongCount":3}]}
        """
        let transport = MockTransport()
        transport.body = Data(json.utf8)
        let api = makeAPI(transport: transport)

        let stats = try await api.stats()
        XCTAssertTrue(stats.hasAttempts)
        XCTAssertEqual(stats.bestScore, 780)
        XCTAssertEqual(stats.weakAreas.first?.wrongRate ?? 0, 0.75, accuracy: 1e-9)
    }

    func testStudyHistoryAggregatesDrillStats() {
        let ai901 = """
        {"q1":{"questionId":"q1","attempts":3,"correct":2,"lastResult":"correct","lastSeenAt":2000},
         "q2":{"questionId":"q2","attempts":1,"correct":0,"lastSeenAt":1000}}
        """
        let pl300 = """
        {"q9":{"questionId":"q9","attempts":5,"correct":5,"lastSeenAt":9000}}
        """
        let rows = [
            ProgressEntry(storageKey: "exam-prep-drill-stats:AI901", data: ai901, updatedAt: 0),
            ProgressEntry(storageKey: "exam-prep-drill-stats:PL300", data: pl300, updatedAt: 0),
            ProgressEntry(storageKey: "exam-prep-reading:AI901", data: "{}", updatedAt: 0), // ignored
        ]
        let activity = StudyHistory.activity(from: rows)

        XCTAssertEqual(activity.count, 2)
        XCTAssertEqual(activity.first?.examId, "PL300")       // most recent (9000)
        XCTAssertEqual(activity.first?.questionsSeen, 1)
        let ai = activity.first { $0.examId == "AI901" }
        XCTAssertEqual(ai?.questionsSeen, 2)
        XCTAssertEqual(ai?.attempts, 4)
        XCTAssertEqual(ai?.accuracy ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(StudyHistory.totalQuestionsSeen(activity), 3)
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
