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

    /// False when no user is signed in — the widget shows a "Sign in" prompt.
    public var signedIn: Bool
    public var inProgressCount: Int
    public var inQueueCount: Int
    public var totalParts: Int
    public var totalValue: Double
    public var inProgress: [InProgressProject]
    public var updatedAt: Date

    public init(signedIn: Bool = true, inProgressCount: Int = 0, inQueueCount: Int = 0,
                totalParts: Int = 0, totalValue: Double = 0, inProgress: [InProgressProject] = [],
                updatedAt: Date = Date()) {
        self.signedIn = signedIn; self.inProgressCount = inProgressCount
        self.inQueueCount = inQueueCount; self.totalParts = totalParts
        self.totalValue = totalValue; self.inProgress = inProgress; self.updatedAt = updatedAt
    }

    /// The empty, signed-out state (used as the widget placeholder and after
    /// sign-out).
    public static let signedOut = WorkshopWidgetSnapshot(signedIn: false)

    /// A representative sample for the widget gallery / previews.
    public static let sample = WorkshopWidgetSnapshot(
        signedIn: true, inProgressCount: 2, inQueueCount: 5, totalParts: 34, totalValue: 210.50,
        inProgress: [.init(id: 1, title: "Walnut Dining Table", partsCount: 18, difficulty: "Intermediate"),
                     .init(id: 2, title: "Hand Tool Storage Cabinet", partsCount: 16, difficulty: "Advanced")])
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
}
