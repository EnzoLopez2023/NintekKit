import XCTest
@testable import NintekKit

final class BambuModelsTests: XCTestCase {
    private func snakeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func testDecodesStatusOnlyProviderConnectionsResponse() throws {
        let json = """
        {"thingiverse":{"connected":true,"source":"account","storage_configured":true}}
        """

        let response = try snakeDecoder().decode(ProviderConnectionsResponse.self, from: Data(json.utf8))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encoded = try encoder.encode(response.thingiverse)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertTrue(response.thingiverse.connected)
        XCTAssertEqual(response.thingiverse.source, .account)
        XCTAssertTrue(response.thingiverse.storageConfigured)
        XCTAssertEqual(Set(object.keys), ["connected", "source", "storage_configured"])
        XCTAssertNil(object["token"])
    }

    func testDecodesFutureThingiverseConnectionSource() throws {
        let json = """
        {"connected":true,"source":"managed_identity","storage_configured":true}
        """

        let status = try snakeDecoder().decode(ThingiverseConnectionStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.source, .unknown)
    }

    func testDecodesBambuListRowWithoutDetailAssets() throws {
        let json = """
        {"id":12,"title":"Gridfinity Bin","source_url":"https://makerworld.com/en/models/123",
         "source_site":"makerworld","source_model_id":"123","description":"A useful bin",
         "creator_name":"Maker","license_name":"CC BY-NC","image_count":4,"file_count":2,
         "import_warnings":["Original files require MakerWorld sign-in"],
         "hero_asset_id":91,"created_at":"2026-08-29","updated_at":"2026-08-30"}
        """

        let project = try snakeDecoder().decode(BambuProject.self, from: Data(json.utf8))

        XCTAssertEqual(project.sourceSite, .makerworld)
        XCTAssertEqual(project.sourceModelId, "123")
        XCTAssertEqual(project.imageCount, 4)
        XCTAssertEqual(project.fileCount, 2)
        XCTAssertEqual(project.heroAssetId, 91)
        XCTAssertEqual(project.importWarnings, ["Original files require MakerWorld sign-in"])
        XCTAssertTrue(project.assets.isEmpty)
    }

    func testDecodesBareBambuUpdateResponseWithAggregateDefaults() throws {
        let json = """
        {"id":12,"title":"Gridfinity Bin","source_url":"https://makerworld.com/en/models/123",
         "source_site":"makerworld","source_model_id":"123","description":null,
         "creator_name":null,"license_name":null,"hero_asset_id":null,
         "created_at":"2026-08-29","updated_at":"2026-08-30"}
        """

        let project = try snakeDecoder().decode(BambuProject.self, from: Data(json.utf8))

        XCTAssertTrue(project.assets.isEmpty)
        XCTAssertEqual(project.imageCount, 0)
        XCTAssertEqual(project.fileCount, 0)
        XCTAssertTrue(project.importWarnings.isEmpty)
    }

    func testDecodesBambuDetailAndFutureEnumValues() throws {
        let json = """
        {"id":12,"title":"Gridfinity Bin","source_url":"https://models.example/123",
         "source_site":"future_library","source_model_id":null,"description":null,
         "creator_name":null,"license_name":null,
         "assets":[{"id":91,"bambu_project_id":12,"kind":"future_asset",
                    "filename":"bin.mesh","content_type":"application/octet-stream",
                    "size_bytes":2048,"original_url":"https://files.example/bin.mesh","sort_order":0}],
         "image_count":0,"file_count":1,"hero_asset_id":null,
         "created_at":"2026-08-29","updated_at":"2026-08-30"}
        """

        let project = try snakeDecoder().decode(BambuProject.self, from: Data(json.utf8))

        XCTAssertEqual(project.sourceSite, .unknown)
        XCTAssertEqual(project.assets.first?.kind, .unknown)
        XCTAssertEqual(project.assets.first?.bambuProjectId, 12)
        XCTAssertEqual(project.assets.first?.sizeBytes, 2048)
    }

    func testDecodesBambuAnalysisAndImportWarnings() throws {
        let analysisJSON = """
        {"source_site":"printables","source_model_id":"abc","title":"Clamp",
         "description":"Printable clamp","creator_name":"Builder","license_name":"GPL",
         "preview_image_url":"https://img.example/clamp.jpg","image_count":3,"file_count":2,
         "files":[{"filename":"clamp.3mf","kind":"model"},{"filename":"notes.pdf","kind":"file"}],
         "warnings":["Original files require provider authentication"]}
        """
        let analysisWithoutWarningsJSON = """
        {"source_site":"makerworld","source_model_id":"xyz","title":"Bracket",
         "description":"Printable bracket","creator_name":null,"license_name":null,
         "preview_image_url":null,"image_count":1,"file_count":1,
         "files":[{"filename":"bracket.3mf","kind":"model"}]}
        """
        let importJSON = """
        {"project":{"id":7,"title":"Clamp","source_url":"https://printables.com/model/abc",
                    "source_site":"printables","source_model_id":"abc","description":"Printable clamp",
                    "creator_name":"Builder","license_name":"GPL","assets":[],
                    "image_count":0,"file_count":0,"hero_asset_id":null,
                    "created_at":"2026-08-29","updated_at":"2026-08-30"},
         "warnings":["notes.pdf was blocked"]}
        """

        let analysis = try snakeDecoder().decode(BambuAnalysisResult.self, from: Data(analysisJSON.utf8))
        let analysisWithoutWarnings = try snakeDecoder().decode(
            BambuAnalysisResult.self,
            from: Data(analysisWithoutWarningsJSON.utf8)
        )
        let result = try snakeDecoder().decode(BambuImportResult.self, from: Data(importJSON.utf8))

        XCTAssertEqual(analysis.sourceSite, .printables)
        XCTAssertEqual(analysis.previewImageUrl, "https://img.example/clamp.jpg")
        XCTAssertEqual(analysis.files.map(\.kind), [.model, .file])
        XCTAssertEqual(analysis.warnings, ["Original files require provider authentication"])
        XCTAssertTrue(analysisWithoutWarnings.warnings.isEmpty)
        XCTAssertEqual(result.project.title, "Clamp")
        XCTAssertEqual(result.warnings, ["notes.pdf was blocked"])
    }
}
