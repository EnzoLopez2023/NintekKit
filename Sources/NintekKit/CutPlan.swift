import Foundation

// Near-verbatim port of `src/lib/cutPlan.ts` (the web's guillotine/BSSF cut-plan
// optimizer). Pure Swift, no NintekKit-model dependency beyond `CutListItem`, so
// it's fully unit-testable in isolation. Kept structurally identical to the web
// source (same function names/shapes) to make future diffs against the web
// source easy to spot.

// MARK: - Types

/// A piece of stock material available to cut from (a sheet size × quantity).
/// Numeric mirror of the web's stock row after its text fields are parsed —
/// see `StockRow`/`CutPlanConfig` in WorkshopModels.swift for the raw
/// string-field config that's persisted and edited in the UI.
public struct StockSheet: Sendable, Equatable {
    public let id: String
    public let length: Double
    public let width: Double
    public let qty: Int
    public let label: String
    public let thickness: String

    public init(id: String, length: Double, width: Double, qty: Int, label: String, thickness: String) {
        self.id = id; self.length = length; self.width = width
        self.qty = qty; self.label = label; self.thickness = thickness
    }
}

/// One physical piece to be cut (a cut-list row expanded `qty` times).
public struct CutPiece: Sendable, Equatable {
    public let id: String
    public let partName: String
    public let length: Double
    public let width: Double
    public let material: String
    public let thickness: String
}

/// A piece placed on a sheet at a specific position (post-optimization).
public struct PlacedPiece: Sendable, Equatable {
    public let pieceId: String
    public let partName: String
    public let length: Double
    public let width: Double
    public let x: Double
    public let y: Double
}

/// One sheet's full layout — every piece placed on it plus waste%.
public struct SheetLayout: Sendable, Equatable {
    public let sheetIndex: Int
    public let stockId: String
    public let sheetLength: Double
    public let sheetWidth: Double
    public let placed: [PlacedPiece]
    public let wastePercent: Double
}

/// The optimizer's full output.
public struct CutPlanResult: Sendable, Equatable {
    public let layouts: [SheetLayout]
    public let totalSheets: Int
    public let overallYieldPercent: Double
    public let totalCuts: Int
    public var skippedPieces: [String]   // populated by the buildCutPieces caller
    public let unplacedPieces: [String]
}

// MARK: - Rendering helpers (ported from CutPlanSheet.tsx)

/// Warm, muted swatches cycled across distinct part names — matches the web's
/// `PALETTE` exactly (same hex values) so sheet diagrams look identical.
public let cutPlanPalette: [String] = [
    "#C8A882", "#8FB4A8", "#B8916E", "#7A9BB5", "#C4A96B",
    "#A68B9E", "#6FAF8A", "#C47A72", "#7FAFC4", "#B8A07A",
]

/// Assigns each distinct part name a stable color, in first-seen order across
/// all sheets — matches the web's `buildColorMap`.
public func buildColorMap(_ layouts: [SheetLayout]) -> [String: String] {
    var map: [String: String] = [:]
    var idx = 0
    for layout in layouts {
        for p in layout.placed where map[p.partName] == nil {
            map[p.partName] = cutPlanPalette[idx % cutPlanPalette.count]
            idx += 1
        }
    }
    return map
}

/// Formats inches as a mixed-number fractional label (nearest 1/8", falling
/// back to 2-decimal) — matches the web's `fmtDim` exactly, including its
/// tolerance windows for snapping to a fraction.
public func fmtDim(_ inches: Double) -> String {
    let whole = Int(inches.rounded(.down))
    let frac = inches - Double(whole)
    if frac < 0.01 { return "\(whole)\"" }
    let fracs: [(Double, String)] = [
        (0.125, "⅛"), (0.25, "¼"), (0.375, "⅜"), (0.5, "½"),
        (0.625, "⅝"), (0.75, "¾"), (0.875, "⅞"),
    ]
    if let match = fracs.first(where: { abs(frac - $0.0) < 0.04 }) {
        return whole > 0 ? "\(whole)\(match.1)\"" : "\(match.1)\""
    }
    return String(format: "%.2f\"", inches)
}

// MARK: - Dimension parser

private let vulgarFractions: [Character: Double] = [
    "½": 0.5, "¼": 0.25, "¾": 0.75,
    "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875,
]
private let vulgarPattern = "[½¼¾⅛⅜⅝⅞]"

/// Parses free-text dimension strings into inches. Handles feet+inches
/// (`1' 11½`, `2' 8`, `2'`), vulgar fractions (`27½`, `½`), simple fractions
/// (`27 1/2`, `3/4`), decimals (`27.5`, `.5`), and smart-quote variants of `'`/`"`.
/// Ported verbatim from the web's `parseInches` — this is the one piece of the
/// whole native port with real correctness risk, so keep the branch order and
/// regexes exactly in sync with the TypeScript source if either changes.
public func parseInches(_ raw: String?) -> Double? {
    guard let raw else { return nil }
    var s = raw
        .replacingOccurrences(of: "\u{2019}", with: "'")   // ’
        .replacingOccurrences(of: "\u{2018}", with: "'")   // ‘
        .replacingOccurrences(of: "\u{201C}", with: "\"")  // “
        .replacingOccurrences(of: "\u{201D}", with: "\"")  // ”
        .replacingOccurrences(of: "''", with: "\"")
    s = s.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { return nil }

    func firstMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound { groups.append("") }
            else if let range = Range(r, in: s) { groups.append(String(s[range])) }
            else { groups.append("") }
        }
        return groups
    }

    // 1. Feet + inch + vulgar fraction: 1' 11½
    if let m = firstMatch("^(\\d+)'\\s*(\\d+)\\s*(\(vulgarPattern))"),
       let feet = Double(m[1]), let inch = Double(m[2]), let frac = m[3].first, let v = vulgarFractions[frac] {
        let total = feet * 12 + inch + v
        return total > 0 ? total : nil
    }

    // 2. Feet + inch + simple fraction: 1' 11 3/4
    if let m = firstMatch("^(\\d+)'\\s*(\\d+)\\s+(\\d+)/(\\d+)"),
       let feet = Double(m[1]), let inch = Double(m[2]), let num = Double(m[3]), let den = Double(m[4]), den != 0 {
        let total = feet * 12 + inch + num / den
        return total > 0 ? total : nil
    }

    // 3. Feet + inches (decimal ok): 2' 8  or  2'8  or  2' 8.5
    if let m = firstMatch("^(\\d+)'\\s*(\\d+(?:\\.\\d+)?)"),
       let feet = Double(m[1]), let inch = Double(m[2]) {
        let total = feet * 12 + inch
        return total > 0 ? total : nil
    }

    // 4. Feet only: 2'
    if let m = firstMatch("^(\\d+)'\\s*$"), let feet = Double(m[1]) {
        let total = feet * 12
        return total > 0 ? total : nil
    }

    // 5. Whole + vulgar fraction: 27½  or  ½ alone
    if let m = firstMatch("^(\\d+)?\\s*(\(vulgarPattern))"),
       let frac = m[2].first, let v = vulgarFractions[frac] {
        let whole = m[1].isEmpty ? 0 : (Double(m[1]) ?? 0)
        let total = whole + v
        return total > 0 ? total : nil
    }

    // 6. Whole + simple fraction: 27 1/2
    if let m = firstMatch("^(\\d+)\\s+(\\d+)/(\\d+)"),
       let whole = Double(m[1]), let num = Double(m[2]), let den = Double(m[3]), den != 0 {
        let total = whole + num / den
        return total > 0 ? total : nil
    }

    // 7. Simple fraction alone: 3/4
    if let m = firstMatch("^(\\d+)/(\\d+)"),
       let num = Double(m[1]), let den = Double(m[2]), den != 0 {
        let total = num / den
        return total > 0 ? total : nil
    }

    // 8. Decimal or integer (leading dot ok): 27.5  or  .5
    if let m = firstMatch("^(\\d*\\.?\\d+)"), let v = Double(m[1]) {
        return v > 0 ? v : nil
    }

    return nil
}

// MARK: - Build cut pieces from a project's cut list

/// Expands a project's cut-list rows (each with a `qty`) into individual
/// `CutPiece`s, parsing their length/width. Rows whose dimensions don't parse
/// are collected into `skipped` (by part name) rather than silently dropped.
public func buildCutPieces(_ cutList: [CutListItem]) -> (pieces: [CutPiece], skipped: [String]) {
    var pieces: [CutPiece] = []
    var skipped: [String] = []

    for item in cutList {
        guard let l = parseInches(item.length), let w = parseInches(item.width) else {
            skipped.append(item.partName)
            continue
        }
        let qty = max(1, item.qty)
        for i in 0..<qty {
            pieces.append(CutPiece(
                id: "\(item.id)-\(i)",
                partName: item.partName,
                length: l, width: w,
                material: (item.material ?? "").lowercased(),
                thickness: (item.thickness ?? "").lowercased()
            ))
        }
    }

    return (pieces, skipped)
}

// MARK: - Guillotine cut optimizer

private struct FreeRect {
    var x: Double, y: Double, w: Double, h: Double
}

/// Reference type (matches the web's mutable object) — placePiece mutates
/// `placed`/`freeRects` in place as pieces land on this sheet.
private final class OpenSheet {
    let stockId: String
    let sheetLength: Double
    let sheetWidth: Double
    var placed: [PlacedPiece] = []
    var freeRects: [FreeRect]

    init(stockId: String, sheetLength: Double, sheetWidth: Double, freeRects: [FreeRect]) {
        self.stockId = stockId; self.sheetLength = sheetLength; self.sheetWidth = sheetWidth
        self.freeRects = freeRects
    }
}

private func normalizeMatchText(_ s: String) -> String {
    let noQuotes = s.replacingOccurrences(of: "[\"\u{201D}\u{201C}]", with: "", options: .regularExpression)
    let collapsed = noQuotes.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return collapsed.lowercased().trimmingCharacters(in: .whitespaces)
}

private func thicknessMatches(_ stockThickness: String, _ pieceThickness: String) -> Bool {
    if stockThickness.trimmingCharacters(in: .whitespaces).isEmpty { return true }
    if let stockT = parseInches(stockThickness), let pieceT = parseInches(pieceThickness) {
        return abs(stockT - pieceT) < 0.005
    }
    // Fall back to normalized string contains when one side isn't numeric.
    let sn = normalizeMatchText(stockThickness)
    let pn = normalizeMatchText(pieceThickness)
    return !pn.isEmpty && pn.contains(sn)
}

private func matchesMaterial(_ piece: CutPiece, _ stock: StockSheet) -> Bool {
    if !thicknessMatches(stock.thickness, piece.thickness) { return false }

    let tokens = normalizeMatchText(stock.label).split(separator: " ").map(String.init).filter { !$0.isEmpty }
    if tokens.isEmpty { return true }
    let haystack = normalizeMatchText("\(piece.material) \(piece.thickness)")
    if haystack.isEmpty { return false }
    return tokens.allSatisfy { haystack.contains($0) }
}

/// Best Short Side Fit score: lower is better. `w`/`h` on `rect` map to the
/// x/y axes (piece.length → x, piece.width → y), matching the web's SVG
/// viewBox convention (x=0..sheetLength, y=0..sheetWidth).
private func bssfScore(_ pieceL: Double, _ pieceW: Double, _ rect: FreeRect) -> Double? {
    if pieceL > rect.w || pieceW > rect.h { return nil }
    let leftoverShort = min(rect.w - pieceL, rect.h - pieceW)
    let leftoverLong  = max(rect.w - pieceL, rect.h - pieceW)
    return leftoverShort * 1_000_000 + leftoverLong
}

private func guillotineSplit(_ rect: FreeRect, _ pieceL: Double, _ pieceW: Double, _ kerf: Double) -> [FreeRect] {
    // rightoverW: horizontal space to the right of the piece (x-axis).
    // topoverH:   vertical space below the piece (y-axis).
    let rightoverW = rect.w - pieceL - kerf
    let topoverH   = rect.h - pieceW - kerf
    var result: [FreeRect] = []

    if rightoverW < topoverH {
        // Narrower gap is to the right — split that side first (limited to piece height).
        if rightoverW > 0 {
            result.append(FreeRect(x: rect.x + pieceL + kerf, y: rect.y, w: rightoverW, h: pieceW))
        }
        // Full-width strip below.
        if topoverH > 0 {
            result.append(FreeRect(x: rect.x, y: rect.y + pieceW + kerf, w: rect.w, h: topoverH))
        }
    } else {
        // Narrower gap is below — split that side first (limited to piece width).
        if topoverH > 0 {
            result.append(FreeRect(x: rect.x, y: rect.y + pieceW + kerf, w: pieceL, h: topoverH))
        }
        // Full-height strip to the right.
        if rightoverW > 0 {
            result.append(FreeRect(x: rect.x + pieceL + kerf, y: rect.y, w: rightoverW, h: rect.h))
        }
    }

    return result
}

private func placePiece(_ sheet: OpenSheet, _ rectIdx: Int, _ piece: CutPiece, _ kerf: Double, rotated: Bool = false) {
    let rect = sheet.freeRects[rectIdx]
    let pl = rotated ? piece.width : piece.length
    let pw = rotated ? piece.length : piece.width
    sheet.placed.append(PlacedPiece(pieceId: piece.id, partName: piece.partName, length: pl, width: pw, x: rect.x, y: rect.y))
    let newRects = guillotineSplit(rect, pl, pw, kerf)
    sheet.freeRects.replaceSubrange(rectIdx...rectIdx, with: newRects)
}

/// Preserves first-occurrence order (matches JS's `[...new Set(arr)]`, whose
/// iteration order is insertion order — Swift's `Set` has no such guarantee).
private func orderedUnique(_ items: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for item in items where !seen.contains(item) {
        seen.insert(item)
        result.append(item)
    }
    return result
}

/// Packs `pieces` onto `stocks` sheets using a largest-piece-first, best-short-
/// side-fit guillotine algorithm — near-verbatim port of the web's
/// `optimizeCuts`. `skippedPieces` on the result is always empty here (the
/// caller populates it from `buildCutPieces`'s `skipped`, matching the web's
/// two-step flow).
public func optimizeCuts(stocks: [StockSheet], pieces: [CutPiece], kerf: Double) -> CutPlanResult {
    var remaining: [String: Int] = [:]
    for s in stocks { remaining[s.id] = s.qty }
    var openSheets: [OpenSheet] = []
    var unplacedPieces: [String] = []

    let sorted = pieces.sorted { $0.length * $0.width > $1.length * $1.width }

    for piece in sorted {
        var bestScore = Double.infinity
        var bestSheet = -1
        var bestRect = -1
        var bestRotated = false

        for si in openSheets.indices {
            let sheet = openSheets[si]
            guard let stock = stocks.first(where: { $0.id == sheet.stockId }), matchesMaterial(piece, stock) else { continue }

            for ri in sheet.freeRects.indices {
                let rect = sheet.freeRects[ri]
                if let score = bssfScore(piece.length, piece.width, rect), score < bestScore {
                    bestScore = score; bestSheet = si; bestRect = ri; bestRotated = false
                }
                if piece.length != piece.width, let scoreR = bssfScore(piece.width, piece.length, rect), scoreR < bestScore {
                    bestScore = scoreR; bestSheet = si; bestRect = ri; bestRotated = true
                }
            }
        }

        if bestSheet >= 0 {
            placePiece(openSheets[bestSheet], bestRect, piece, kerf, rotated: bestRotated)
        } else {
            let matchingStock = stocks.first { stock in
                matchesMaterial(piece, stock) &&
                (remaining[stock.id] ?? 0) > 0 &&
                ((piece.length <= stock.length && piece.width <= stock.width) ||
                 (piece.length != piece.width && piece.width <= stock.length && piece.length <= stock.width))
            }

            if let matchingStock {
                remaining[matchingStock.id] = (remaining[matchingStock.id] ?? 0) - 1
                let newSheet = OpenSheet(stockId: matchingStock.id, sheetLength: matchingStock.length, sheetWidth: matchingStock.width,
                                         freeRects: [FreeRect(x: 0, y: 0, w: matchingStock.length, h: matchingStock.width)])
                openSheets.append(newSheet)
                let rect0 = newSheet.freeRects[0]
                let score = bssfScore(piece.length, piece.width, rect0)
                let scoreR = piece.length != piece.width ? bssfScore(piece.width, piece.length, rect0) : nil
                let rotated = scoreR != nil && (score == nil || scoreR! < score!)
                if score != nil || scoreR != nil {
                    placePiece(newSheet, 0, piece, kerf, rotated: rotated)
                } else {
                    unplacedPieces.append(piece.partName)
                }
            } else {
                unplacedPieces.append(piece.partName)
            }
        }
    }

    let layouts: [SheetLayout] = openSheets.enumerated().map { i, sheet in
        let usedArea = sheet.placed.reduce(0.0) { $0 + $1.length * $1.width }
        let totalArea = sheet.sheetLength * sheet.sheetWidth
        let wastePercent = totalArea > 0 ? (1 - usedArea / totalArea) * 100 : 100
        return SheetLayout(sheetIndex: i, stockId: sheet.stockId, sheetLength: sheet.sheetLength,
                           sheetWidth: sheet.sheetWidth, placed: sheet.placed, wastePercent: wastePercent)
    }

    let totalSheetArea = layouts.reduce(0.0) { $0 + $1.sheetLength * $1.sheetWidth }
    let totalUsedArea = layouts.reduce(0.0) { $0 + $1.placed.reduce(0.0) { $0 + $1.length * $1.width } }
    let overallYieldPercent = totalSheetArea > 0 ? (totalUsedArea / totalSheetArea) * 100 : 0
    let totalPiecesPlaced = layouts.reduce(0) { $0 + $1.placed.count }

    return CutPlanResult(
        layouts: layouts,
        totalSheets: layouts.count,
        overallYieldPercent: overallYieldPercent,
        totalCuts: totalPiecesPlaced,
        skippedPieces: [],
        unplacedPieces: orderedUnique(unplacedPieces)
    )
}
