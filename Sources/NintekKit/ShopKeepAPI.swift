import Foundation

/// Typed wrapper over the ShopKeep Express API (per-user SQLite behind Entra
/// JWT auth). Thin by design — one async method per route, sharing NintekKit's
/// `APIClient` (bearer-token transport). The server returns snake_case JSON, so
/// this configures the decoder with `.convertFromSnakeCase`.
public struct ShopKeepAPI: Sendable {
    private let client: APIClient

    /// Production ShopKeep backend (same origin the web app uses).
    public static let productionBaseURL = URL(string: "https://app-shopkeep-prod-lwxhu7jxlrbtu.azurewebsites.net")!

    public init(baseURL: URL = ShopKeepAPI.productionBaseURL,
                tokenProvider: TokenProvider,
                transport: HTTPTransport = URLSession.shared) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.client = APIClient(baseURL: baseURL, tokenProvider: tokenProvider,
                                transport: transport, decoder: decoder, encoder: encoder)
    }

    /// Backend origin — used to build authenticated image URLs.
    public var baseURL: URL { client.baseURL }

    // MARK: Dashboard

    public func stats() async throws -> DashboardStats {
        try await client.get("/api/stats")
    }

    public func categoryStats() async throws -> [CategoryCount] {
        try await client.get("/api/stats/categories")
    }

    public func recentTools(limit: Int = 5) async throws -> [Tool] {
        try await client.get("/api/tools/recent?limit=\(limit)")
    }

    public func alerts() async throws -> Alerts {
        try await client.get("/api/alerts")
    }

    // MARK: Inventory

    /// Filtered tool list. All filters optional; nil = no constraint.
    public func tools(search: String? = nil, category: String? = nil, brand: String? = nil,
                      status: String? = nil, condition: String? = nil,
                      storageLocation: String? = nil, subLocation: String? = nil) async throws -> [Tool] {
        var q: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            if let value, !value.isEmpty { q.append(URLQueryItem(name: name, value: value)) }
        }
        add("search", search); add("category", category); add("brand", brand)
        add("status", status); add("condition", condition)
        add("storage_location", storageLocation); add("sub_location", subLocation)

        var comps = URLComponents()
        comps.path = "/api/tools"
        comps.queryItems = q.isEmpty ? nil : q
        return try await client.get(comps.string ?? "/api/tools")
    }

    public func tool(id: Int) async throws -> Tool {
        try await client.get("/api/tools/\(id)")
    }

    /// Soft-deleted tools (Trash).
    public func trash() async throws -> [Tool] {
        try await client.get("/api/tools/trash")
    }

    // MARK: Tool writes

    @discardableResult
    public func createTool(_ input: ToolInput) async throws -> Tool {
        try await client.post("/api/tools", body: input)
    }

    @discardableResult
    public func updateTool(id: Int, _ input: ToolInput) async throws -> Tool {
        try await client.put("/api/tools/\(id)", body: input)
    }

    public func softDeleteTool(id: Int) async throws {
        try await client.delete("/api/tools/\(id)", as: EmptyResponse.self)
    }

    public func bulkDeleteTools(ids: [Int]) async throws {
        struct Body: Encodable { let ids: [Int] }
        // DELETE with a body — send via the generic client.
        try await client.deleteWithBody("/api/tools/bulk", body: Body(ids: ids), as: EmptyResponse.self)
    }

    public func restoreTool(id: Int) async throws {
        try await client.post("/api/tools/\(id)/restore", body: EmptyBody(), as: EmptyResponse.self)
    }

    public func permanentlyDeleteTool(id: Int) async throws {
        try await client.delete("/api/tools/\(id)/permanent", as: EmptyResponse.self)
    }

    // MARK: Lifecycle

    public func checkOut(id: Int, by name: String, notes: String? = nil, dueDate: String? = nil) async throws {
        struct Body: Encodable { let checkedOutBy: String; let notes: String?; let dueDate: String? }
        try await client.post("/api/tools/\(id)/checkout",
                              body: Body(checkedOutBy: name, notes: notes, dueDate: dueDate), as: EmptyResponse.self)
    }

    public func checkIn(id: Int) async throws {
        try await client.post("/api/tools/\(id)/checkin", body: EmptyBody(), as: EmptyResponse.self)
    }

    public func sendToMaintenance(id: Int, description: String? = nil) async throws {
        struct Body: Encodable { let description: String? }
        try await client.post("/api/tools/\(id)/maintenance", body: Body(description: description), as: EmptyResponse.self)
    }

    public func markSold(id: Int) async throws {
        try await client.post("/api/tools/\(id)/sold", body: EmptyBody(), as: EmptyResponse.self)
    }

    // MARK: Reports

    public func spendingSummary() async throws -> SpendingSummary {
        try await client.get("/api/reports/spending-summary")
    }

    public func spendingByYear() async throws -> [YearSpend] {
        try await client.get("/api/reports/spending-by-year")
    }

    public func checkoutHistory(limit: Int = 20) async throws -> [CheckoutRecord] {
        try await client.get("/api/reports/checkout-history?limit=\(limit)")
    }

    // MARK: Settings

    public func activityLog(limit: Int = 100) async throws -> ActivityResponse {
        try await client.get("/api/activity-log?limit=\(limit)")
    }

    public func locations() async throws -> [SKLocation] {
        try await client.get("/api/settings/locations")
    }

    /// Authenticated file downloads (bytes) — native writes to a temp file and
    /// shares. The server generates these (pdfkit / SQLite copy), so they can
    /// take a while and are worth reporting progress for.
    public func dossierPDF(onProgress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> Data {
        try await client.getData("/api/export/dossier.pdf", onProgress: onProgress)
    }
    public func databaseBackup(onProgress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> Data {
        try await client.getData("/api/backup/database", onProgress: onProgress)
    }

    // MARK: Images

    /// Upload a tool photo. The server expects a camelCase base64 body
    /// (`imageName`/`imageData`/`imageType`), so this posts raw JSON.
    public func uploadImage(toolId: Int, imageName: String, jpeg: Data, imageType: String = "image/jpeg") async throws {
        struct Body: Encodable { let imageName: String; let imageData: String; let imageType: String }
        let body = Body(imageName: imageName, imageData: jpeg.base64EncodedString(), imageType: imageType)
        try await client.postRawJSON("/api/tools/\(toolId)/images", jsonBody: JSONEncoder().encode(body), as: EmptyResponse.self)
    }

    public func deleteImage(imageId: Int) async throws {
        try await client.delete("/api/tools/images/\(imageId)", as: EmptyResponse.self)
    }

    /// Fetch an image's bytes with the bearer token (native uses the header, not
    /// the web `?oid=` param).
    public func imageData(_ image: ToolImage) async throws -> Data {
        var path = "/api/tools/images/\(image.id)"
        if let size = image.imageSize { path += "?v=private-v2-\(size)" }
        return try await client.getData(path)
    }

    /// Authenticated URL for an image's bytes. Native must attach the bearer
    /// token as a header when loading it (the web `?oid=` param is not used).
    public func imageURL(_ image: ToolImage) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/tools/images/\(image.id)"),
                                  resolvingAgainstBaseURL: false)
        if let size = image.imageSize {
            comps?.queryItems = [URLQueryItem(name: "v", value: "private-v2-\(size)")]
        }
        return comps?.url ?? baseURL
    }

    // MARK: Documents

    /// Attach a document (manual / receipt / warranty / other). The server
    /// expects a camelCase base64 body (`docName`/`docData`/`docType`/`docLabel`),
    /// so this posts raw JSON like the image upload.
    public func uploadDocument(toolId: Int, docName: String, data: Data,
                               docType: String, docLabel: String) async throws {
        struct Body: Encodable { let docName: String; let docData: String; let docType: String; let docLabel: String }
        let body = Body(docName: docName, docData: data.base64EncodedString(), docType: docType, docLabel: docLabel)
        try await client.postRawJSON("/api/tools/\(toolId)/documents", jsonBody: JSONEncoder().encode(body), as: EmptyResponse.self)
    }

    public func deleteDocument(docId: Int) async throws {
        try await client.delete("/api/tools/documents/\(docId)", as: EmptyResponse.self)
    }

    /// Fetch a document's bytes with the bearer token (for share / preview).
    public func documentData(_ doc: ToolDocument) async throws -> Data {
        try await client.getData("/api/tools/documents/\(doc.id)")
    }

    // MARK: Settings — Categories

    private struct NameBody: Encodable { let name: String }

    public func categories() async throws -> [SKCategory] {
        try await client.get("/api/settings/categories")
    }
    @discardableResult
    public func createCategory(name: String) async throws -> SKCategory {
        try await client.post("/api/settings/categories", body: NameBody(name: name))
    }
    @discardableResult
    public func renameCategory(id: Int, name: String) async throws -> SKCategory {
        try await client.put("/api/settings/categories/\(id)", body: NameBody(name: name))
    }
    public func deleteCategory(id: Int) async throws {
        try await client.delete("/api/settings/categories/\(id)", as: EmptyResponse.self)
    }
    @discardableResult
    public func addSubCategory(categoryId: Int, name: String) async throws -> SKSubCategory {
        try await client.post("/api/settings/categories/\(categoryId)/subcategories", body: NameBody(name: name))
    }
    @discardableResult
    public func renameSubCategory(id: Int, name: String) async throws -> SKSubCategory {
        try await client.put("/api/settings/subcategories/\(id)", body: NameBody(name: name))
    }
    public func deleteSubCategory(id: Int) async throws {
        try await client.delete("/api/settings/subcategories/\(id)", as: EmptyResponse.self)
    }

    // MARK: Settings — Locations

    @discardableResult
    public func createLocation(name: String) async throws -> SKLocation {
        try await client.post("/api/settings/locations", body: NameBody(name: name))
    }
    @discardableResult
    public func renameLocation(id: Int, name: String) async throws -> SKLocation {
        try await client.put("/api/settings/locations/\(id)", body: NameBody(name: name))
    }
    public func deleteLocation(id: Int) async throws {
        try await client.delete("/api/settings/locations/\(id)", as: EmptyResponse.self)
    }
    @discardableResult
    public func addSubLocation(locationId: Int, name: String) async throws -> SKSubLocation {
        try await client.post("/api/settings/locations/\(locationId)/sublocations", body: NameBody(name: name))
    }
    @discardableResult
    public func renameSubLocation(id: Int, name: String) async throws -> SKSubLocation {
        try await client.put("/api/settings/sublocations/\(id)", body: NameBody(name: name))
    }
    public func deleteSubLocation(id: Int) async throws {
        try await client.delete("/api/settings/sublocations/\(id)", as: EmptyResponse.self)
    }

    // MARK: Settings — Favorite suppliers

    private struct SupplierBody: Encodable {
        let name: String
        let url: String
    }

    public func suppliers() async throws -> [FavoriteSupplier] {
        try await client.get("/api/settings/suppliers")
    }
    @discardableResult
    public func createSupplier(name: String, url: String) async throws -> FavoriteSupplier {
        try await client.post("/api/settings/suppliers", body: SupplierBody(name: name, url: url))
    }
    @discardableResult
    public func updateSupplier(id: Int, name: String, url: String) async throws -> FavoriteSupplier {
        try await client.put("/api/settings/suppliers/\(id)", body: SupplierBody(name: name, url: url))
    }
    public func deleteSupplier(id: Int) async throws {
        try await client.delete("/api/settings/suppliers/\(id)", as: EmptyResponse.self)
    }
    public func reorderSuppliers(ids: [Int]) async throws {
        struct Body: Encodable { let ids: [Int] }
        try await client.put("/api/settings/suppliers/reorder", body: Body(ids: ids), as: EmptyResponse.self)
    }
}
