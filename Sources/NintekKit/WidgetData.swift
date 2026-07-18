import Foundation

/// The small snapshot the app publishes for its home-screen widget. Written by
/// the app after study actions, read by the widget extension — shared across the
/// process boundary via an App Group.
public struct WidgetData: Codable, Sendable, Equatable {
    public var streak: Int
    public var studiedToday: Bool
    public var focusExamCode: String?   // e.g. "PL-300"
    public var cardsDue: Int?           // due in the focus exam
    public var bestScore: Int?          // focus exam best score, /1000
    public var updatedAt: Date

    public init(streak: Int, studiedToday: Bool, focusExamCode: String? = nil,
                cardsDue: Int? = nil, bestScore: Int? = nil, updatedAt: Date = Date()) {
        self.streak = streak; self.studiedToday = studiedToday
        self.focusExamCode = focusExamCode; self.cardsDue = cardsDue
        self.bestScore = bestScore; self.updatedAt = updatedAt
    }
}

/// Reads/writes ``WidgetData`` in the shared App Group so the app and the widget
/// extension see the same values. The App Group must be enabled on both targets
/// (portal capability `group.com.nintek.cairn`).
public enum CairnWidgetStore {
    public static let appGroup = "group.com.nintek.cairn"
    private static let key = "cairn.widget.data"

    public static func save(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let encoded = try? JSONEncoder().encode(data) else { return }
        defaults.set(encoded, forKey: key)
    }

    public static func load() -> WidgetData? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let raw = defaults.data(forKey: key),
              let data = try? JSONDecoder().decode(WidgetData.self, from: raw) else { return nil }
        return data
    }

    /// Merge a partial update into the stored snapshot (keeps existing fields).
    public static func update(_ mutate: (inout WidgetData) -> Void) {
        var data = load() ?? WidgetData(streak: 0, studiedToday: false)
        mutate(&data)
        data.updatedAt = Date()
        save(data)
    }
}
