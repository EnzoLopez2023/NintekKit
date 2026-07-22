import XCTest
@testable import NintekKit

/// Decode tests for the Workshop API models. These lock in the decoder gotchas
/// documented in WorkshopModels.swift against realistic server payloads:
///  • snake_case → camelCase via `.convertFromSnakeCase` (matching WorkshopAPI),
///  • dimensions as free-text Strings, `purchased` as a real Bool,
///  • aggregate fields optional so the bare create/update response decodes,
///  • the camelCase cut-plan-config round-tripping through a plain coder.
final class WorkshopModelsTests: XCTestCase {

    /// Mirrors the decoder WorkshopAPI configures for the snake_case API.
    private func snakeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func testDecodesProjectListRowWithAggregates() throws {
        let json = """
        {"id":7,"title":"Bookshelf","description":null,"source_url":null,"cut_plan_url":null,
         "status":"in_progress","difficulty":"Advanced","estimated_hours":12,
         "wood_types":["Walnut","Maple"],"tools_needed":["Router"],
         "parts_count":9,"total_cost":142.5,"hero_image_id":3,
         "cut_list_names":"Side Shelf","material_names":"Screws",
         "created_at":"2026-01-01","updated_at":"2026-02-02"}
        """
        let p = try snakeDecoder().decode(WSProject.self, from: Data(json.utf8))
        XCTAssertEqual(p.id, 7)
        XCTAssertEqual(p.status, .inProgress)
        XCTAssertEqual(p.difficulty, .advanced)
        XCTAssertEqual(p.woodTypes, ["Walnut", "Maple"])
        XCTAssertEqual(p.partsCount, 9)
        XCTAssertEqual(p.totalCost, 142.5)
        XCTAssertEqual(p.heroImageId, 3)
        XCTAssertNil(p.description)
    }

    /// Create/update return a BARE row — aggregates absent. Must still decode.
    func testDecodesBareCreateResponse() throws {
        let json = """
        {"id":8,"title":"Stool","description":"three legs","source_url":null,"cut_plan_url":null,
         "status":"idea","difficulty":"Beginner","estimated_hours":0,
         "wood_types":[],"tools_needed":[],
         "created_at":"2026-03-01","updated_at":"2026-03-01"}
        """
        let p = try snakeDecoder().decode(WSProject.self, from: Data(json.utf8))
        XCTAssertEqual(p.id, 8)
        XCTAssertEqual(p.status, .idea)
        XCTAssertNil(p.partsCount)   // aggregate absent → nil, not a decode failure
        XCTAssertNil(p.heroImageId)
        XCTAssertTrue(p.woodTypes.isEmpty)
    }

    func testDecodesDetailWithStringDimsAndBoolPurchased() throws {
        let json = """
        {"id":7,"title":"Bookshelf","description":null,"source_url":null,"cut_plan_url":null,
         "status":"completed","difficulty":"Intermediate","estimated_hours":5,
         "wood_types":["Oak"],"tools_needed":[],
         "images":[{"id":1,"project_id":7,"kind":"sketch","image_type":"application/pdf",
                    "image_url":null,"sort_order":0}],
         "cut_list":[{"id":2,"project_id":7,"part_name":"Shelf","qty":3,
                      "length":"27 1/2","width":"11","thickness":"3/4","material":"Oak","sort_order":0}],
         "materials":[{"id":4,"project_id":7,"name":"Screws","qty_label":"1 box","cost":8.0,
                       "purchased":true,"sort_order":0}],
         "total_cost":8.0,"parts_count":3,
         "build_log":[{"id":5,"project_id":7,"note":"Glue-up","file_path":"a.jpg",
                       "image_type":"image/jpeg","created_at":"2026-04-01"}],
         "finish_log":[{"id":6,"project_id":7,"product_name":"Danish Oil","finish_type":"oil",
                        "color":null,"coats":2,"notes":null,"applied_at":"2026-04-05"}],
         "links":[{"id":9,"relationship":"related","linked_id":10,"linked_title":"Table",
                   "linked_status":"planning"}],
         "created_at":"2026-01-01","updated_at":"2026-02-02"}
        """
        let d = try snakeDecoder().decode(WSProjectDetail.self, from: Data(json.utf8))
        XCTAssertEqual(d.cutList.first?.length, "27 1/2")   // string, not Double
        XCTAssertEqual(d.cutList.first?.thickness, "3/4")
        XCTAssertTrue(d.images.first!.isPDF)
        XCTAssertEqual(d.materials.first?.purchased, true)  // real Bool
        XCTAssertTrue(d.buildLog.first!.hasPhoto)
        XCTAssertEqual(d.finishLog.first?.coats, 2)
        XCTAssertEqual(d.links.first?.linkedStatus, .planning)
    }

    func testDecodesShoppingItem() throws {
        let json = """
        {"id":4,"project_id":7,"name":"Screws","qty_label":"1 box","cost":8.0,
         "purchased":false,"sort_order":0,"project_title":"Bookshelf"}
        """
        let s = try snakeDecoder().decode(ShoppingItem.self, from: Data(json.utf8))
        XCTAssertEqual(s.projectTitle, "Bookshelf")
        XCTAssertFalse(s.purchased)
    }

    /// The shaper LIST omits images/cut_list (detail-only) — they must decode to
    /// [] rather than throwing keyNotFound (the bug caught on-device 2026-07-22).
    func testDecodesShaperListRowWithoutImagesOrCutList() throws {
        let json = """
        {"id":3,"title":"Inlay Tray","shaper_url":"https://shaper.so/x","description":null,
         "photo_url":"https://img/x.jpg","materials":[{"name":"Walnut","qty":"1 bd ft"}],
         "instructions":null,"hero_image_id":null,
         "created_at":"2026-01-01","updated_at":"2026-01-02"}
        """
        let s = try snakeDecoder().decode(ShaperProject.self, from: Data(json.utf8))
        XCTAssertEqual(s.title, "Inlay Tray")
        XCTAssertEqual(s.materials.first?.name, "Walnut")
        XCTAssertTrue(s.images.isEmpty)   // absent key → [], not a throw
        XCTAssertTrue(s.cutList.isEmpty)
    }

    func testUnknownEnumFallback() throws {
        let json = #"{"status":"archived_v2"}"#
        struct Holder: Decodable { let status: ProjectStatus }
        let h = try snakeDecoder().decode(Holder.self, from: Data(json.utf8))
        XCTAssertEqual(h.status, .unknown)   // resilient to new server values
    }

    /// The cut-plan-config blob is camelCase and shared verbatim with the web
    /// app. A plain coder (no key strategy) must preserve `stockRows`/`lengthStr`.
    func testCutPlanConfigRoundTripsCamelCase() throws {
        let json = """
        {"config":{"stockRows":[{"id":"abc","lengthStr":"96","widthStr":"48",
                                 "thicknessStr":"0.75","qtyStr":"2","label":"4x8"}],
                   "kerfStr":"0.125"}}
        """
        struct Resp: Decodable { let config: CutPlanConfig? }
        let plain = JSONDecoder()
        let cfg = try plain.decode(Resp.self, from: Data(json.utf8)).config
        XCTAssertEqual(cfg?.stockRows.first?.lengthStr, "96")
        XCTAssertEqual(cfg?.kerfStr, "0.125")

        // Re-encode with a plain encoder and confirm the camelCase keys survive.
        let out = try JSONEncoder().encode(cfg)
        let s = String(data: out, encoding: .utf8)!
        XCTAssertTrue(s.contains("stockRows"))
        XCTAssertTrue(s.contains("lengthStr"))
        XCTAssertFalse(s.contains("stock_rows"))
    }
}
