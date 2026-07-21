import Foundation

/// The compact, glanceable snapshot ShopKeep publishes for its home-screen and
/// Lock Screen widgets. Written by the app after it loads dashboard data (the
/// app owns MSAL/Apple auth), read by the widget extension. Shared across the
/// process boundary via the App Group — so the widget never needs to
/// authenticate or hit the network itself, which is what keeps it reliable
/// within WidgetKit's tight refresh budget.
public struct ShopKeepWidgetSnapshot: Codable, Sendable, Equatable {
    /// One slice of the "by category" breakdown.
    public struct Category: Codable, Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let count: Int
        public init(name: String, count: Int) { self.name = name; self.count = count }
    }

    /// A recently-added tool, flattened to just what a widget row shows.
    public struct RecentTool: Codable, Sendable, Equatable, Identifiable {
        public let id: Int
        public let name: String
        public let subtitle: String   // e.g. "Router · Festool"
        public let condition: String  // raw ToolCondition value (drives the dot color)
        public init(id: Int, name: String, subtitle: String, condition: String) {
            self.id = id; self.name = name; self.subtitle = subtitle; self.condition = condition
        }
    }

    /// False when no user is signed in — the widget shows a "Sign in" prompt.
    public var signedIn: Bool
    public var totalTools: Int
    public var needsAttention: Int
    public var checkedOut: Int
    public var totalValue: Double
    public var categories: [Category]
    public var recent: [RecentTool]
    public var updatedAt: Date

    public init(signedIn: Bool = true, totalTools: Int = 0, needsAttention: Int = 0,
                checkedOut: Int = 0, totalValue: Double = 0, categories: [Category] = [],
                recent: [RecentTool] = [], updatedAt: Date = Date()) {
        self.signedIn = signedIn; self.totalTools = totalTools
        self.needsAttention = needsAttention; self.checkedOut = checkedOut
        self.totalValue = totalValue; self.categories = categories
        self.recent = recent; self.updatedAt = updatedAt
    }

    /// The empty, signed-out state (used as the widget placeholder and after
    /// sign-out).
    public static let signedOut = ShopKeepWidgetSnapshot(signedIn: false)

    /// A representative sample for the widget gallery / previews.
    public static let sample = ShopKeepWidgetSnapshot(
        signedIn: true, totalTools: 248, needsAttention: 6, checkedOut: 3, totalValue: 42800,
        categories: [.init(name: "Routers", count: 34), .init(name: "Saws", count: 28),
                     .init(name: "Clamps", count: 22), .init(name: "Sanders", count: 18)],
        recent: [.init(id: 1, name: "OF 1400 Router", subtitle: "Router · Festool", condition: "excellent"),
                 .init(id: 2, name: "Track Saw Rail", subtitle: "Accessory · TSO", condition: "good"),
                 .init(id: 3, name: "Bench Chisel Set", subtitle: "Hand Tool · Narex", condition: "fair")])
}

/// Reads/writes ``ShopKeepWidgetSnapshot`` in the shared App Group so the app and
/// the widget extension see the same values. The App Group must be enabled on
/// both targets (portal capability `group.com.nintek.shopkeep`).
public enum ShopKeepWidgetStore {
    public static let appGroup = "group.com.nintek.shopkeep"
    private static let key = "shopkeep.widget.snapshot"

    public static func save(_ snapshot: ShopKeepWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: key)
    }

    public static func load() -> ShopKeepWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let raw = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ShopKeepWidgetSnapshot.self, from: raw) else { return nil }
        return snapshot
    }

    /// Replace the stored snapshot with the signed-out state (call on sign-out).
    public static func clear() { save(.signedOut) }
}
