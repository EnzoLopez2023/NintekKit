import XCTest
@testable import NintekKit

final class NintekKitTests: XCTestCase {

    private var skDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func testCairnSurfaceRemainsReexported() {
        let _: NintekKit.ExamMeta.Type = ExamMeta.self
        let _: NintekKit.ExamAttempt.Type = ExamAttempt.self
        let _: NintekKit.FlashcardSM2.Type = FlashcardSM2.self
        let _: NintekKit.StudyHistory.Type = StudyHistory.self
        let _: NintekKit.StudyStats.Type = StudyStats.self
        let _: NintekKit.QuestionResult.Type = QuestionResult.self
        let snapshot: NintekKit.WidgetData = WidgetData(streak: 3, studiedToday: true)
        XCTAssertEqual(snapshot.streak, 3)
        XCTAssertTrue(snapshot.studiedToday)
    }

    /// `NintekKitTare` is a dedicated product now, but every symbol it exports
    /// must still resolve through the aggregate `import NintekKit` — Cairn,
    /// ShopKeep, and Workshop consumers link the aggregate, not the split
    /// product, and this must not become a breaking change for them.
    func testTareSurfaceRemainsReexported() {
        let _: NintekKit.TareWidgetSnapshot.Type = TareWidgetSnapshot.self
        let _: NintekKit.TareWidgetStore.Type = TareWidgetStore.self
        let _: NintekKit.TareWatchLogEntry.Type = TareWatchLogEntry.self
        let _: NintekKit.TareWatchPayload.Type = TareWatchPayload.self
        let _: NintekKit.TareDoseActivityWindow.Type = TareDoseActivityWindow.self
        let snapshot: NintekKit.TareWidgetSnapshot = TareWidgetSnapshot.sample
        XCTAssertNotNil(snapshot.doseMg)
        XCTAssertEqual(TareWidgetStore.appGroup, "group.com.nintek.tare")
    }

    func testDecodesDashboardStats() throws {
        let json = #"{"total_tools":433,"needs_attention":3,"checked_out":0,"total_value":53976.5}"#
        let stats = try skDecoder.decode(DashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.totalTools, 433)
        XCTAssertEqual(stats.needsAttention, 3)
        XCTAssertEqual(stats.totalValue, 53976.5, accuracy: 1e-6)
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
        let tool = try XCTUnwrap(tools.first)
        XCTAssertEqual(tool.id, 7)
        XCTAssertEqual(tool.brand, "Microjig")
        XCTAssertNil(tool.model)
        XCTAssertEqual(tool.purchasePrice ?? 0, 375.0, accuracy: 1e-6)
        XCTAssertEqual(tool.quantity, 1)
        XCTAssertEqual(tool.toolStatus, .maintenance)
        XCTAssertEqual(tool.toolCondition, .good)
        XCTAssertEqual(tool.firstImage?.imageSize, 48213)
    }

    func testNewToolInputDoesNotAssumeOtherCategory() {
        XCTAssertEqual(ToolInput(name: "Router").category, "")
    }

    func testAlertsAttentionIdsAreDistinctAcrossBuckets() throws {
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
}
