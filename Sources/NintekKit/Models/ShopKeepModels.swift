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
    public var documents: [ToolDocument]?

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

/// A document attached to a tool (`tool_documents`; label = manual/receipt/
/// warranty/other). Bytes fetched from `/api/tools/documents/:id`.
public struct ToolDocument: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public var label: String?
    public var fileName: String?
    public var fileType: String?
    public var uploadedAt: String?
}

/// Body for creating/updating a tool (`POST`/`PUT /api/tools`). Encoded to
/// snake_case by ShopKeepAPI. All fields optional except name/category.
public struct ToolInput: Codable, Sendable, Equatable {
    public var name: String
    public var category: String
    public var condition: String
    public var status: String
    public var subCategory: String?
    public var brand: String?
    public var model: String?
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

    public init(name: String, category: String = "Other", condition: String = "good", status: String = "available") {
        self.name = name; self.category = category; self.condition = condition; self.status = status
    }

    /// Prefill from an existing tool (for the edit form).
    public init(from tool: Tool) {
        name = tool.name; category = tool.category; condition = tool.condition; status = tool.status
        subCategory = tool.subCategory; brand = tool.brand; model = tool.model
        storageLocation = tool.storageLocation; subLocation = tool.subLocation
        purchaseDate = tool.purchaseDate; purchasePrice = tool.purchasePrice; qty = tool.qty
        purchasedFrom = tool.purchasedFrom; productUrl = tool.productUrl; sku = tool.sku
        barcode = tool.barcode; productDetail = tool.productDetail; orderNumber = tool.orderNumber
        notes = tool.notes; lastMaintained = tool.lastMaintained; warrantyExpires = tool.warrantyExpires
        maintenanceIntervalDays = tool.maintenanceIntervalDays; nextMaintenanceDate = tool.nextMaintenanceDate
        lowStockThreshold = tool.lowStockThreshold
    }
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

// MARK: - Reports

/// `GET /api/reports/spending-summary`.
public struct SpendingSummary: Codable, Sendable, Equatable {
    public struct TopTool: Codable, Sendable, Equatable { public let name: String?; public let purchasePrice: Double? }
    public struct TopYear: Codable, Sendable, Equatable { public let year: String?; public let count: Int?; public let total: Double? }
    public let total: Double
    public let avgPrice: Double
    public let topTool: TopTool?
    public let topYear: TopYear?
    public let toolsWithPrice: Int
}

/// One year of spend (`GET /api/reports/spending-by-year`).
public struct YearSpend: Codable, Identifiable, Sendable, Equatable {
    public var id: String { year }
    public let year: String
    public let count: Int
    public let total: Double
    public let avgPrice: Double
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
