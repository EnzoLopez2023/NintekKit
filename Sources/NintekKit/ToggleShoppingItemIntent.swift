#if os(iOS)
import AppIntents

/// The Home Screen shopping-list widget's "check off" button (Phase 7.2).
/// Lives in NintekKit (not the widget extension or the app) because it must
/// be visible to *both*: the widget extension's `Button(intent:)` declares
/// it, and — since this has no `openAppWhenRun` — it actually executes in
/// the extension's own process, with no network access and nothing to
/// authenticate with. It just records the intent via `WorkshopWidgetStore`;
/// the app performs the real, authenticated write next time it opens.
public struct ToggleShoppingItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check Off Shopping Item"

    @Parameter(title: "Item ID")
    public var itemId: Int

    public init() {}
    public init(itemId: Int) { self.itemId = itemId }

    public func perform() async throws -> some IntentResult {
        // Optimistic: drop it from the cached snapshot so the widget updates
        // instantly, without waiting on the app to reconcile.
        if var snapshot = WorkshopWidgetStore.load() {
            snapshot.shoppingItems.removeAll { $0.id == itemId }
            WorkshopWidgetStore.save(snapshot)
        }
        WorkshopWidgetStore.requestShoppingToggle(itemId: itemId)
        return .result()
    }
}
#endif
