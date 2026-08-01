#if os(iOS)
import ActivityKit

/// Live Activity for an active shopping trip (Phase 7.9+) — a Lock Screen /
/// Dynamic Island checklist for checking off materials while walking a store
/// aisle, mirroring `CutListActivityAttributes`'s shape. Unlike the cut-list
/// checklist, checking an item off here *is* a real, persisted purchase —
/// the extension still can't authenticate, so `ToggleShoppingActivityItemIntent`
/// updates this Activity's own state for immediate feedback *and* queues the
/// real write through the same `WorkshopWidgetStore` reconciliation path the
/// Phase 7.2 widget button already uses.
public struct ShoppingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var purchasedItemIds: Set<Int>
        public init(purchasedItemIds: Set<Int> = []) {
            self.purchasedItemIds = purchasedItemIds
        }
    }

    /// One row's worth of the shopping list, flattened to just what the Live
    /// Activity's UI shows — fixed for the lifetime of the activity.
    public struct ItemSummary: Codable, Hashable, Sendable {
        public let id: Int
        public let name: String
        public let qtyLabel: String?
        public init(id: Int, name: String, qtyLabel: String?) {
            self.id = id; self.name = name; self.qtyLabel = qtyLabel
        }
    }

    public let items: [ItemSummary]

    public init(items: [ItemSummary]) {
        self.items = items
    }
}
#endif
