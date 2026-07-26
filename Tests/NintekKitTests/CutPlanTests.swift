import XCTest
@testable import NintekKit

/// Tests for the `cutPlan.ts` → `CutPlan.swift` port. `parseInches` is the
/// highest-risk piece of the whole native port (per the port plan) — every
/// branch is covered here, plus the concrete cases called out explicitly:
/// `1' 11½`, `27 3/4`, `.5`, and smart-quote normalization.
final class CutPlanTests: XCTestCase {

    // MARK: parseInches — explicitly called-out cases

    func testFeetInchVulgarFraction() {
        XCTAssertEqual(parseInches("1' 11½"), 23.5)
    }

    func testWholeSimpleFraction() {
        XCTAssertEqual(parseInches("27 3/4"), 27.75)
    }

    func testLeadingDotDecimal() {
        XCTAssertEqual(parseInches(".5"), 0.5)
    }

    func testSmartQuoteNormalization() {
        // Curly apostrophe (’, U+2019) in place of a straight ' — e.g. iOS's
        // autocorrect turning a typed ' into a curly quote mid-entry.
        XCTAssertEqual(parseInches("2\u{2019} 8"), 32)
        // Realistic full smart-quote input: 2'-8" typed with curly ’ and ” —
        // the trailing inch mark is simply ignored (parseInches only needs a
        // prefix match), matching the web's behavior.
        XCTAssertEqual(parseInches("2\u{2019} 8\u{201D}"), 32)
    }

    // MARK: parseInches — full branch coverage

    func testFeetInchSimpleFraction() {
        XCTAssertEqual(parseInches("1' 11 3/4"), 23.75)
    }

    func testFeetInchesDecimalNoSpace() {
        XCTAssertEqual(parseInches("2'8"), 32)
    }

    func testFeetInchesDecimalWithSpace() {
        XCTAssertEqual(parseInches("2' 8"), 32)
    }

    func testFeetInchesDecimalFractionalInches() {
        XCTAssertEqual(parseInches("2' 8.5"), 32.5)
    }

    func testFeetOnly() {
        XCTAssertEqual(parseInches("2'"), 24)
    }

    func testWholePlusVulgarFraction() {
        XCTAssertEqual(parseInches("27½"), 27.5)
    }

    func testVulgarFractionAlone() {
        XCTAssertEqual(parseInches("½"), 0.5)
    }

    func testSimpleFractionAlone() {
        XCTAssertEqual(parseInches("3/4"), 0.75)
    }

    func testPlainDecimal() {
        XCTAssertEqual(parseInches("27.5"), 27.5)
    }

    func testPlainInteger() {
        XCTAssertEqual(parseInches("14"), 14)
    }

    func testOtherVulgarFractions() {
        XCTAssertEqual(parseInches("¼"), 0.25)
        XCTAssertEqual(parseInches("⅛"), 0.125)
        XCTAssertEqual(parseInches("⅜"), 0.375)
        XCTAssertEqual(parseInches("⅝"), 0.625)
        XCTAssertEqual(parseInches("⅞"), 0.875)
    }

    // MARK: parseInches — edge cases

    func testNilInput() {
        XCTAssertNil(parseInches(nil))
    }

    func testEmptyString() {
        XCTAssertNil(parseInches(""))
    }

    func testWhitespaceOnly() {
        XCTAssertNil(parseInches("   "))
    }

    func testZeroIsRejected() {
        // Every branch requires `v > 0`, matching the web (a zero-length part
        // makes no sense, so it's treated as unparseable rather than valid-zero).
        XCTAssertNil(parseInches("0"))
    }

    func testGarbageInput() {
        XCTAssertNil(parseInches("abc"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(parseInches("  27.5  "), 27.5)
    }

    // MARK: buildCutPieces

    private func cutListItem(json: String) throws -> CutListItem {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CutListItem.self, from: Data(json.utf8))
    }

    func testBuildCutPiecesExpandsByQty() throws {
        let item = try cutListItem(json: """
        {"id":5,"project_id":1,"part_name":"Shelf","qty":3,"length":"27 1/2","width":"11",
         "thickness":"3/4","material":"Oak","sort_order":0}
        """)
        let (pieces, skipped) = buildCutPieces([item])
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces.map(\.id), ["5-0", "5-1", "5-2"])
        XCTAssertEqual(pieces[0].length, 27.5)
        XCTAssertEqual(pieces[0].width, 11)
        XCTAssertEqual(pieces[0].material, "oak")   // lowercased
        XCTAssertEqual(pieces[0].thickness, "3/4")
    }

    func testBuildCutPiecesSkipsUnparseableDimensions() throws {
        let item = try cutListItem(json: """
        {"id":6,"project_id":1,"part_name":"Mystery Part","qty":1,"length":"who knows","width":"11",
         "thickness":null,"material":null,"sort_order":0}
        """)
        let (pieces, skipped) = buildCutPieces([item])
        XCTAssertTrue(pieces.isEmpty)
        XCTAssertEqual(skipped, ["Mystery Part"])
    }

    func testBuildCutPiecesQtyFloorsAtOne() throws {
        // qty is a non-optional Int in the model, but guard the max(1, qty)
        // floor behavior explicitly in case a caller ever passes 0.
        let item = try cutListItem(json: """
        {"id":7,"project_id":1,"part_name":"Leg","qty":0,"length":"4","width":"4",
         "thickness":null,"material":null,"sort_order":0}
        """)
        let (pieces, _) = buildCutPieces([item])
        XCTAssertEqual(pieces.count, 1)
    }

    // MARK: optimizeCuts

    func testOptimizeCutsPlacesFittingPieces() {
        let stock = StockSheet(id: "s1", length: 96, width: 48, qty: 1, label: "", thickness: "")
        let pieces = [
            CutPiece(id: "p1-0", partName: "Side A", length: 40, width: 20, material: "", thickness: ""),
            CutPiece(id: "p2-0", partName: "Side B", length: 40, width: 20, material: "", thickness: ""),
        ]
        let result = optimizeCuts(stocks: [stock], pieces: pieces, kerf: 0.125)
        XCTAssertEqual(result.totalSheets, 1)
        XCTAssertEqual(result.totalCuts, 2)
        XCTAssertTrue(result.unplacedPieces.isEmpty)
        XCTAssertEqual(result.layouts.first?.placed.count, 2)
    }

    func testOptimizeCutsReportsUnplacedWhenTooBig() {
        let stock = StockSheet(id: "s1", length: 96, width: 48, qty: 1, label: "", thickness: "")
        let pieces = [
            CutPiece(id: "p1-0", partName: "Giant Slab", length: 200, width: 100, material: "", thickness: ""),
        ]
        let result = optimizeCuts(stocks: [stock], pieces: pieces, kerf: 0.125)
        XCTAssertEqual(result.totalSheets, 0)
        XCTAssertEqual(result.unplacedPieces, ["Giant Slab"])
    }

    func testOptimizeCutsRespectsMaterialMismatch() {
        // Stock labeled "plywood" should refuse a piece whose material/thickness
        // text doesn't mention "plywood" anywhere.
        let stock = StockSheet(id: "s1", length: 96, width: 48, qty: 1, label: "plywood", thickness: "")
        let piece = CutPiece(id: "p1-0", partName: "Oak Leg", length: 10, width: 10, material: "oak", thickness: "")
        let result = optimizeCuts(stocks: [stock], pieces: [piece], kerf: 0.125)
        XCTAssertEqual(result.totalSheets, 0)
        XCTAssertEqual(result.unplacedPieces, ["Oak Leg"])
    }

    func testOptimizeCutsRotatesToFit() {
        // A 60×10 piece doesn't fit lengthwise-first on a 48×96 sheet unless
        // rotated (48 < 60), but does fit rotated (10 ≤ 48, 60 ≤ 96).
        let stock = StockSheet(id: "s1", length: 48, width: 96, qty: 1, label: "", thickness: "")
        let piece = CutPiece(id: "p1-0", partName: "Long Rail", length: 60, width: 10, material: "", thickness: "")
        let result = optimizeCuts(stocks: [stock], pieces: [piece], kerf: 0.125)
        XCTAssertEqual(result.totalCuts, 1)
        XCTAssertTrue(result.unplacedPieces.isEmpty)
    }

    func testOptimizeCutsRunsOutOfStockQty() {
        // Only 1 sheet available; a 2nd non-fitting-alongside piece that needs
        // its own new sheet should go unplaced once stock is exhausted.
        let stock = StockSheet(id: "s1", length: 48, width: 48, qty: 1, label: "", thickness: "")
        let pieces = [
            CutPiece(id: "p1-0", partName: "Big One", length: 47, width: 47, material: "", thickness: ""),
            CutPiece(id: "p2-0", partName: "Second One", length: 47, width: 47, material: "", thickness: ""),
        ]
        let result = optimizeCuts(stocks: [stock], pieces: pieces, kerf: 0.125)
        XCTAssertEqual(result.totalSheets, 1)
        XCTAssertEqual(result.totalCuts, 1)
        XCTAssertEqual(result.unplacedPieces, ["Second One"])
    }
}
