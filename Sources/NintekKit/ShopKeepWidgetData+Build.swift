import Foundation

/// Builds a ``ShopKeepWidgetSnapshot`` from the live API models the Dashboard
/// already loads, so the app publishes widget data with a single call and the
/// flattening logic (which fields a widget row shows) lives in one place.
public extension ShopKeepWidgetSnapshot {
    init(stats: DashboardStats, categories: [CategoryCount], recent: [Tool], maxRecent: Int = 4) {
        self.init(
            signedIn: true,
            totalTools: stats.totalTools,
            needsAttention: stats.needsAttention,
            checkedOut: stats.checkedOut,
            totalValue: stats.totalValue,
            categories: categories
                .sorted { $0.count > $1.count }
                .prefix(6)
                .map { Category(name: $0.category, count: $0.count) },
            recent: recent.prefix(maxRecent).map { tool in
                let subtitle = [tool.category, tool.brand].compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                return RecentTool(id: tool.id, name: tool.name, subtitle: subtitle, condition: tool.condition)
            },
            updatedAt: Date()
        )
    }
}
