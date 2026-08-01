import Foundation

/// The compact, glanceable snapshot Workshop publishes for its home-screen
/// widgets. Written by the app after it loads dashboard data (the app owns
/// MSAL/Apple auth), read by the widget extension. Shared across the process
/// boundary via the App Group — so the widget never needs to authenticate or
/// hit the network itself, which is what keeps it reliable within WidgetKit's
/// tight refresh budget.
public struct WorkshopWidgetSnapshot: Codable, Sendable, Equatable {
    /// A project currently "In Progress", flattened to just what a widget row shows.
    public struct InProgressProject: Codable, Sendable, Equatable, Identifiable {
        public let id: Int
        public let title: String
        public let partsCount: Int
        public let difficulty: String
        public init(id: Int, title: String, partsCount: Int, difficulty: String) {
            self.id = id; self.title = title; self.partsCount = partsCount; self.difficulty = difficulty
        }
    }

    /// A shopping-list row, flattened to just what the widget's checkbox row
    /// needs. Only ever holds *unpurchased* items — the widget's whole point
    /// is a quick "check this off" action.
    public struct ShoppingPreviewItem: Codable, Sendable, Equatable, Identifiable {
        public let id: Int
        public let name: String
        public let qtyLabel: String?
        public init(id: Int, name: String, qtyLabel: String?) {
            self.id = id; self.name = name; self.qtyLabel = qtyLabel
        }
    }

    /// False when no user is signed in — the widget shows a "Sign in" prompt.
    public var signedIn: Bool
    public var inProgressCount: Int
    public var inQueueCount: Int
    public var totalParts: Int
    public var totalValue: Double
    public var inProgress: [InProgressProject]
    public var shoppingItems: [ShoppingPreviewItem]
    public var updatedAt: Date

    public init(signedIn: Bool = true, inProgressCount: Int = 0, inQueueCount: Int = 0,
                totalParts: Int = 0, totalValue: Double = 0, inProgress: [InProgressProject] = [],
                shoppingItems: [ShoppingPreviewItem] = [], updatedAt: Date = Date()) {
        self.signedIn = signedIn; self.inProgressCount = inProgressCount
        self.inQueueCount = inQueueCount; self.totalParts = totalParts
        self.totalValue = totalValue; self.inProgress = inProgress
        self.shoppingItems = shoppingItems; self.updatedAt = updatedAt
    }

    /// The empty, signed-out state (used as the widget placeholder and after
    /// sign-out).
    public static let signedOut = WorkshopWidgetSnapshot(signedIn: false)

    /// A representative sample for the widget gallery / previews.
    public static let sample = WorkshopWidgetSnapshot(
        signedIn: true, inProgressCount: 2, inQueueCount: 5, totalParts: 34, totalValue: 210.50,
        inProgress: [.init(id: 1, title: "Walnut Dining Table", partsCount: 18, difficulty: "Intermediate"),
                     .init(id: 2, title: "Hand Tool Storage Cabinet", partsCount: 16, difficulty: "Advanced")],
        shoppingItems: [.init(id: 1, name: "1 1/4\" pocket screws", qtyLabel: "8"),
                        .init(id: 2, name: "Waterproof wood glue", qtyLabel: "1 bottle")])
}

/// Reads/writes `WorkshopWidgetSnapshot` in the App Group's shared
/// `UserDefaults` suite — the hand-off point between the app and the widget
/// extension.
public enum WorkshopWidgetStore {
    public static let appGroup = "group.com.nintek.workshop"
    private static let key = "workshop.widget.snapshot"

    public static func save(_ snapshot: WorkshopWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }

    public static func load() -> WorkshopWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorkshopWidgetSnapshot.self, from: data)
    }

    /// Resets the shared snapshot to the signed-out placeholder — call on sign-out.
    public static func clear() { save(.signedOut) }

    /// Updates just the shopping-items slice, preserving whatever project
    /// stats were last saved — Dashboard and Shopping List write
    /// independently (different load points), so a plain `save` from either
    /// screen would clobber the other's data.
    public static func mergeShoppingItems(_ items: [WorkshopWidgetSnapshot.ShoppingPreviewItem]) {
        var snapshot = load() ?? .signedOut
        snapshot.signedIn = true
        snapshot.shoppingItems = items
        snapshot.updatedAt = Date()
        save(snapshot)
    }

    // MARK: Interactive-widget hand-off (Phase 7.2)

    /// The widget's "check off" button (and the Phase 7.9+ shopping Live
    /// Activity's rows) run in the extension's own process with no app
    /// launch and no network — they can't safely authenticate, so each tap
    /// just optimistically drops the item from the cached snapshot (for
    /// instant visual feedback) and queues the id here. The app reconciles
    /// the real, authenticated writes the next time it loads (see
    /// `consumePendingShoppingToggles`). A queue rather than a single slot:
    /// a shopping-trip Live Activity session can check off several items
    /// before the app is ever reopened, and a single-slot "last write wins"
    /// would silently drop every toggle but the last one.
    private static let pendingToggleKey = "workshop.widget.pendingShoppingToggleIds"

    public static func requestShoppingToggle(itemId: Int) {
        guard let ud = UserDefaults(suiteName: appGroup) else { return }
        var ids = Set(ud.array(forKey: pendingToggleKey) as? [Int] ?? [])
        ids.insert(itemId)
        ud.set(Array(ids), forKey: pendingToggleKey)
    }

    /// Reads and clears every pending toggle — call once when the app
    /// becomes active so each write actually reaches the server.
    public static func consumePendingShoppingToggles() -> [Int] {
        guard let ud = UserDefaults(suiteName: appGroup),
              let ids = ud.array(forKey: pendingToggleKey) as? [Int], !ids.isEmpty else { return [] }
        ud.removeObject(forKey: pendingToggleKey)
        return ids
    }
}
