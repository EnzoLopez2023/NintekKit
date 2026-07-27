#if os(iOS)
import ActivityKit

/// Live Activity for "cutting a project's parts right now" — a Lock Screen /
/// Dynamic Island checklist you tap off in the shop without unlocking the
/// phone. Deliberately **not** persisted to the server: the web app's
/// `cut_list` table has no "has this piece been cut yet" column, and this
/// checklist is a purely native, in-the-moment tracking aid (it resets each
/// time you start a fresh tracking session) — so it lives entirely in the
/// Activity's own state, no auth/network needed to update it.
public struct CutListActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var checkedPartIds: Set<Int>
        public init(checkedPartIds: Set<Int> = []) {
            self.checkedPartIds = checkedPartIds
        }
    }

    /// One row's worth of the cut list, flattened to just what the Live
    /// Activity's UI shows — fixed for the lifetime of the activity (the
    /// activity is started fresh if the cut list changes).
    public struct PartSummary: Codable, Hashable, Sendable {
        public let id: Int
        public let partName: String
        public let qty: Int
        public init(id: Int, partName: String, qty: Int) {
            self.id = id; self.partName = partName; self.qty = qty
        }
    }

    public let projectId: Int
    public let projectTitle: String
    public let parts: [PartSummary]

    public init(projectId: Int, projectTitle: String, parts: [PartSummary]) {
        self.projectId = projectId; self.projectTitle = projectTitle; self.parts = parts
    }
}
#endif
