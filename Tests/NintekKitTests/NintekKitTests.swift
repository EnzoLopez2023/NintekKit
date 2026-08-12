import XCTest
@testable import NintekKit

/// NintekKit is now a pure content-model + aggregation + SM-2 library (the HTTP
/// layer was removed when Cairn went fully local/CloudKit). These tests cover
/// JSON decoding of the bundled content shapes and the aggregation/SM-2 logic
/// the app relies on.
final class NintekKitTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: Content decoding (bundled JSON shapes)

    func testDecodesCatalog() throws {
        let json = """
        [{"id":"PL300","code":"PL-300","vendor":"Microsoft","title":"Power BI Data Analyst",
          "tagline":"Model, visualize, analyze.","status":"active","level":"Associate",
          "domains":[{"label":"Prepare the data","weight":"25–30%"}],
          "durationMin":100,"passScore":700,"questionCount":116},
         {"id":"AB900","code":"AB-900","vendor":"Microsoft","title":"Coming soon",
          "tagline":"tbd","status":"coming-soon"}]
        """
        let exams = try decoder.decode([ExamMeta].self, from: Data(json.utf8))
        XCTAssertEqual(exams.count, 2)
        XCTAssertTrue(exams[0].isActive)
        XCTAssertEqual(exams[0].domains?.first?.weight, "25–30%")
        XCTAssertFalse(exams[1].isActive)
        XCTAssertNil(exams[1].domains)        // optional fields absent → nil
        XCTAssertNil(exams[1].questionCount)
    }

    func testDecodesFlashcards() throws {
        let json = """
        [{"id":"pl300-fc-001","topic":"DAX","front":"Q?","back":"**A**"}]
        """
        let cards = try decoder.decode([Flashcard].self, from: Data(json.utf8))
        XCTAssertEqual(cards.first?.topic, "DAX")
        XCTAssertEqual(cards.first?.back, "**A**")
    }

    func testDecodesQuestionWithUnknownTypeAndOptionalBlocks() throws {
        // Unknown `type` must decode (→ .unknown), optional blocks absent → nil.
        let json = """
        [{"id":"q1","domain":1,"subdomain":"Storage modes","type":"single","difficulty":"easy",
          "question":"Which mode?","options":["A","B"],"correctAnswers":[1],
          "explanation":"because","examTip":"tip"},
         {"id":"q2","domain":2,"subdomain":"x","type":"drag-drop","difficulty":"hard",
          "question":"Q","options":[],"correctAnswers":[],"explanation":"e"}]
        """
        let qs = try decoder.decode([Question].self, from: Data(json.utf8))
        XCTAssertEqual(qs[0].kind, .single)
        XCTAssertEqual(qs[0].examTip, "tip")
        XCTAssertNil(qs[0].match)
        XCTAssertEqual(qs[1].kind, .unknown)  // future type doesn't break decoding
        XCTAssertEqual(qs[1].domain, 2)
    }

    func testDecodesProgressRows() throws {
        let json = """
        [{"storageKey":"exam-prep-drill-stats:PL300","data":"{\\"x\\":1}","updatedAt":1752760000000}]
        """
        let rows = try decoder.decode([ProgressEntry].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.storageKey, "exam-prep-drill-stats:PL300")
        XCTAssertEqual(rows.first?.updatedAt, 1752760000000)
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
        let back = try decoder.decode(FlashcardStatsMap.self, from: data)
        XCTAssertEqual(back["c1"], stat)
    }

    // MARK: Aggregation

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

    // MARK: ShopKeep decoding (snake_case → camelCase)

    private var skDecoder: JSONDecoder {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }

    func testDecodesDashboardStats() throws {
        let json = #"{"total_tools":433,"needs_attention":3,"checked_out":0,"total_value":53976.5}"#
        let s = try skDecoder.decode(DashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(s.totalTools, 433)
        XCTAssertEqual(s.needsAttention, 3)
        XCTAssertEqual(s.totalValue, 53976.5, accuracy: 1e-6)
    }

    func testDecodesToolWithSnakeCaseAndNulls() throws {
        let json = """
        [{"id":7,"name":"GRR-RIPPER AIR ULTRA '25","category":"Jigs, Fixtures & Templates",
          "condition":"good","status":"maintenance","created_at":"2025-11-18 10:00:00",
          "updated_at":"2025-11-18 10:00:00","brand":"Microjig","model":null,
          "purchase_price":375.0,"storage_location":null,"sub_location":null,"qty":1,
          "sku":"HJP","barcode":null,"next_maintenance_date":"2026-06-30","deleted_at":null,
          "images":[{"id":21,"image_size":48213,"image_type":"image/jpeg"}]}]
        """
        let tools = try skDecoder.decode([Tool].self, from: Data(json.utf8))
        let t = try XCTUnwrap(tools.first)
        XCTAssertEqual(t.id, 7)
        XCTAssertEqual(t.brand, "Microjig")
        XCTAssertNil(t.model)
        XCTAssertEqual(t.purchasePrice ?? 0, 375.0, accuracy: 1e-6)
        XCTAssertEqual(t.quantity, 1)
        XCTAssertEqual(t.toolStatus, .maintenance)
        XCTAssertEqual(t.toolCondition, .good)
        XCTAssertEqual(t.firstImage?.imageSize, 48213)
    }

    func testNewToolInputDoesNotAssumeOtherCategory() {
        XCTAssertEqual(ToolInput(name: "Router").category, "")
    }

    func testAlertsAttentionIdsAreDistinctAcrossBuckets() throws {
        // Same tool can appear in two buckets; ids must dedupe. overdue_checkouts
        // is a lighter shape than the other five (full tool rows).
        func tool(_ id: Int) -> String {
            #"{"id":\#(id),"name":"T\#(id)","category":"C","condition":"good","status":"available","created_at":"x","updated_at":"x"}"#
        }
        let json = """
        {"overdue_maintenance":[\(tool(1)),\(tool(2))],
         "maintenance_upcoming":[\(tool(2))],
         "warranty_expired":[],"warranty_expiring":[\(tool(3))],
         "low_stock":[],
         "overdue_checkouts":[{"id":9,"name":"Drill","category":"Power","brand":"X","due_date":"2026-01-01"}]}
        """
        let alerts = try skDecoder.decode(Alerts.self, from: Data(json.utf8))
        XCTAssertEqual(alerts.attentionToolIds, [1, 2, 3, 9])
        XCTAssertEqual(alerts.overdueCheckouts.first?.dueDate, "2026-01-01")
    }

    func testDecodesFavoriteSuppliers() throws {
        let json = """
        [{"id":4,"name":"Lee Valley","url":"https://www.leevalley.com/","sort_order":2}]
        """
        let suppliers = try skDecoder.decode([FavoriteSupplier].self, from: Data(json.utf8))
        XCTAssertEqual(suppliers, [
            FavoriteSupplier(id: 4, name: "Lee Valley",
                             url: "https://www.leevalley.com/", sortOrder: 2)
        ])
    }

    func testDetailedStatsAggregatesAllSources() {
        let catalog = [
            ExamMeta(id: "AI901", code: "AI-901", vendor: "Microsoft", title: "Azure AI Fundamentals",
                     tagline: "", status: "active", level: nil, domains: nil,
                     durationMin: nil, passScore: nil, questionCount: nil),
        ]
        let rows = [
            ProgressEntry(storageKey: "exam-prep-completed:AI901", data: "[\"s1\",\"s2\",\"s3\"]", updatedAt: 0),
            ProgressEntry(storageKey: "exam-prep-drill-stats:AI901",
                          data: "{\"q1\":{\"questionId\":\"q1\",\"attempts\":3,\"correct\":3,\"lastSeenAt\":5000},\"q2\":{\"questionId\":\"q2\",\"attempts\":2,\"correct\":1,\"lastSeenAt\":4000}}",
                          updatedAt: 0),
            ProgressEntry(storageKey: "exam-prep-analytics:AI901",
                          data: "[{\"completedAt\":9000,\"scoreScaled\":820,\"perQuestion\":[{\"correct\":true,\"subdomain\":\"Vision\"},{\"correct\":false,\"subdomain\":\"Vision\"}]}]",
                          updatedAt: 0),
        ]
        let stats = StudyStats.build(progress: rows, catalog: catalog)

        XCTAssertEqual(stats.totalSectionsComplete, 3)
        XCTAssertEqual(stats.totalQuestionsAnswered, 5)         // 3 + 2 answer events
        let ai = stats.exams.first
        XCTAssertEqual(ai?.sectionsComplete, 3)
        XCTAssertEqual(ai?.questionsAnswered, 5)
        XCTAssertEqual(ai?.drillAccuracy ?? 0, 4.0/5.0, accuracy: 1e-9)   // 4 correct / 5
        XCTAssertEqual(ai?.bestScaledScore, 820)
        XCTAssertEqual(ai?.attemptsCount, 1)
        XCTAssertEqual(stats.bestScaledScore, 820)
        XCTAssertEqual(ai?.subdomains.first?.subdomain, "Vision")
        XCTAssertEqual(ai?.subdomains.first?.attempted, 2)
    }
}
