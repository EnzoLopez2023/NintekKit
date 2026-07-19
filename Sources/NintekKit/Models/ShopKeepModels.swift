import Foundation

// ShopKeep API models. The Express server returns raw SQLite column names
// (snake_case), so `ShopKeepAPI` decodes with `.convertFromSnakeCase` and these
// use camelCase. Nullable columns are optional; NOT-NULL-with-default columns
// that the API always returns are non-optional. `status`/`condition` stay as
// Strings (resilient to new server values) with typed helpers.

/// A tool/inventory item (`GET /api/tools`, `/tools/recent`, `/tools/:id`).
public struct Tool: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let category: String
    public let condition: String
    public let status: String
    public let createdAt: String
    public let updatedAt: String

    public var brand: String?
    public var model: String?
    public var subCategory: String?
    public var storageLocation: String?
    public var subLocation: String?
    public var purchaseDate: String?
    public var purchasePrice: Double?
    public var qty: Int?
    public var purchasedFrom: String?
    public var productUrl: String?
    public var sku: String?
    public var barcode: String?
    public var productDetail: String?
    public var orderNumber: String?
    public var notes: String?
    public var lastMaintained: String?
    public var warrantyExpires: String?
    public var maintenanceIntervalDays: Int?
    public var nextMaintenanceDate: String?
    public var lowStockThreshold: Int?
    public var deletedAt: String?
    public var images: [ToolImage]?

    public var quantity: Int { qty ?? 1 }
    public var toolStatus: ToolStatus { ToolStatus(rawValue: status) ?? .unknown }
    public var toolCondition: ToolCondition { ToolCondition(rawValue: condition) ?? .unknown }
    public var firstImage: ToolImage? { images?.first }
}

/// Tool lifecycle status. Server stores lowercase/underscore values.
public enum ToolStatus: String, Sendable {
    case available
    case checkedOut = "checked_out"
    case maintenance
    case sold
    case unknown
}

public enum ToolCondition: String, Sendable {
    case excellent, good, fair, poor
    case needsRepair = "needs repair"
    case unknown
}

/// One image attached to a tool. The bytes are fetched separately from
/// `/api/tools/images/:id` (native sends a Bearer header). `imageSize` is used
/// as a cache-busting `?v=` param.
public struct ToolImage: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public var imageName: String?
    public var imageType: String?
    public var imageSize: Int?
}

/// Dashboard tiles (`GET /api/stats`).
public struct DashboardStats: Codable, Sendable, Equatable {
    public let totalTools: Int
    public let needsAttention: Int
    public let checkedOut: Int
    public let totalValue: Double
}

/// One slice of the by-category donut (`GET /api/stats/categories`).
public struct CategoryCount: Codable, Identifiable, Sendable, Equatable {
    public var id: String { category }
    public let category: String
    public let count: Int
}

/// One row of `GET /api/alerts` → overdue_checkouts (a tool joined with its
/// open checkout). The other five alert categories are full tool rows.
public struct OverdueCheckout: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public var category: String?
    public var brand: String?
    public var checkedOutBy: String?
    public var checkedOutAt: String?
    public var dueDate: String?
}

/// The six alert buckets (`GET /api/alerts`) that feed "Needs Attention".
public struct Alerts: Codable, Sendable, Equatable {
    public let overdueMaintenance: [Tool]
    public let maintenanceUpcoming: [Tool]
    public let warrantyExpired: [Tool]
    public let warrantyExpiring: [Tool]
    public let lowStock: [Tool]
    public let overdueCheckouts: [OverdueCheckout]

    /// Distinct tool ids needing attention across all buckets — drives the
    /// Dashboard tile count and the tap-through "show me those tools" filter.
    public var attentionToolIds: Set<Int> {
        var ids = Set<Int>()
        for bucket in [overdueMaintenance, maintenanceUpcoming, warrantyExpired, warrantyExpiring, lowStock] {
            ids.formUnion(bucket.map(\.id))
        }
        ids.formUnion(overdueCheckouts.map(\.id))
        return ids
    }
}
