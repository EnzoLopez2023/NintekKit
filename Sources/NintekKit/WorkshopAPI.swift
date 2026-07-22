import Foundation

/// Typed wrapper over the Workshop Express API (per-user SQLite behind dual auth
/// — Entra JWT or an Apple-minted session token). Thin by design: one async
/// method per route in `src/services/api.ts`, sharing NintekKit's `APIClient`.
/// The server returns snake_case JSON, so this configures the decoder with
/// `.convertFromSnakeCase` and the encoder with `.convertToSnakeCase`.
///
/// One exception: the cut-plan-config endpoints round-trip a camelCase JSON blob
/// shared verbatim with the web app, so those two methods use a plain coder.
public struct WorkshopAPI: Sendable {
    private let client: APIClient
    /// Plain coders (no key strategy) for the camelCase cut-plan-config blob.
    private let plainDecoder = JSONDecoder()
    private let plainEncoder = JSONEncoder()

    /// Production Workshop backend (same origin the web app uses).
    public static let productionBaseURL = URL(string: "https://app-workshop-prod-lwxhu7jxlrbtu.azurewebsites.net")!

    public init(baseURL: URL = WorkshopAPI.productionBaseURL,
                tokenProvider: TokenProvider,
                transport: HTTPTransport = URLSession.shared) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.client = APIClient(baseURL: baseURL, tokenProvider: tokenProvider,
                                transport: transport, decoder: decoder, encoder: encoder)
    }

    /// Backend origin — used to build image URLs.
    public var baseURL: URL { client.baseURL }

    // MARK: Projects

    public func listProjects() async throws -> [WSProject] {
        try await client.get("/api/projects")
    }
    public func project(id: Int) async throws -> WSProjectDetail {
        try await client.get("/api/projects/\(id)")
    }
    @discardableResult
    public func createProject(_ input: ProjectInput) async throws -> WSProject {
        try await client.post("/api/projects", body: input)
    }
    @discardableResult
    public func updateProject(id: Int, _ input: ProjectInput) async throws -> WSProject {
        try await client.put("/api/projects/\(id)", body: input)
    }
    public func deleteProject(id: Int) async throws {
        try await client.delete("/api/projects/\(id)", as: EmptyResponse.self)
    }
    public func analyzeProjectURL(_ url: String) async throws -> AnalyzedProject {
        try await client.post("/api/projects/analyze-url", body: URLBody(url: url))
    }

    // MARK: Images

    /// Authenticated-exempt image URL. Workshop's image route carries no bearer
    /// (an `<img>` can't send one), resolving the DB from `?oid=<userKey>`; native
    /// uses the same param.
    public func imageURL(imageId: Int, userKey: String) -> URL {
        oidURL(path: "/api/images/\(imageId)", userKey: userKey)
    }

    /// Upload a sketch/inspiration photo or PDF (multipart `kind` + `file`).
    @discardableResult
    public func uploadImage(projectId: Int, kind: ImageKind, file: MultipartFile) async throws -> WSCreatedID {
        try await client.postMultipart("/api/projects/\(projectId)/images",
                                       fields: ["kind": kind.rawValue], file: file)
    }
    /// Attach an inspiration image by URL (no upload).
    @discardableResult
    public func addInspirationURL(projectId: Int, url: String) async throws -> WSCreatedID {
        try await client.post("/api/projects/\(projectId)/images", body: KindURLBody(kind: "inspiration", url: url))
    }
    public func deleteImage(id: Int) async throws {
        try await client.delete("/api/images/\(id)", as: EmptyResponse.self)
    }

    // MARK: Cut list

    @discardableResult
    public func addCutItem(projectId: Int, _ item: CutListInput) async throws -> WSCreatedID {
        try await client.post("/api/projects/\(projectId)/cut-list", body: item)
    }
    public func updateCutItem(id: Int, _ item: CutListInput) async throws {
        try await client.put("/api/cut-list/\(id)", body: item, as: EmptyResponse.self)
    }
    public func deleteCutItem(id: Int) async throws {
        try await client.delete("/api/cut-list/\(id)", as: EmptyResponse.self)
    }

    // MARK: Materials

    @discardableResult
    public func addMaterial(projectId: Int, _ m: MaterialInput) async throws -> WSCreatedID {
        try await client.post("/api/projects/\(projectId)/materials", body: m)
    }
    public func updateMaterial(id: Int, _ m: MaterialInput) async throws {
        try await client.put("/api/materials/\(id)", body: m, as: EmptyResponse.self)
    }
    public func deleteMaterial(id: Int) async throws {
        try await client.delete("/api/materials/\(id)", as: EmptyResponse.self)
    }
    public func setPurchased(id: Int, purchased: Bool) async throws {
        try await client.patch("/api/materials/\(id)/purchased", body: PurchasedBody(purchased: purchased), as: EmptyResponse.self)
    }

    // MARK: Cut-plan config (camelCase blob — plain coders)

    /// Load the saved optimizer stock/kerf config (or nil if never saved).
    public func cutPlanConfig(projectId: Int) async throws -> CutPlanConfig? {
        let data = try await client.getData("/api/projects/\(projectId)/cut-plan-config")
        return try plainDecoder.decode(CutPlanConfigResponse.self, from: data).config
    }
    /// Save the optimizer config. Sent as raw camelCase JSON so it interoperates
    /// with the web app (which reads/writes the same blob).
    public func saveCutPlanConfig(projectId: Int, _ config: CutPlanConfig) async throws {
        let body = try plainEncoder.encode(config)
        try await client.putRawJSON("/api/projects/\(projectId)/cut-plan-config", jsonBody: body, as: EmptyResponse.self)
    }

    // MARK: Shaper Hub projects

    public func listShaperProjects() async throws -> [ShaperProject] {
        try await client.get("/api/shaper-projects")
    }
    public func shaperProject(id: Int) async throws -> ShaperProject {
        try await client.get("/api/shaper-projects/\(id)")
    }
    @discardableResult
    public func createShaperProject(_ input: ShaperProjectInput) async throws -> ShaperProject {
        try await client.post("/api/shaper-projects", body: input)
    }
    @discardableResult
    public func updateShaperProject(id: Int, _ input: ShaperProjectInput) async throws -> ShaperProject {
        try await client.put("/api/shaper-projects/\(id)", body: input)
    }
    public func deleteShaperProject(id: Int) async throws {
        try await client.delete("/api/shaper-projects/\(id)", as: EmptyResponse.self)
    }
    public func analyzeShaperURL(_ url: String) async throws -> ShaperAnalysisResult {
        try await client.post("/api/shaper-projects/analyze-url", body: URLBody(url: url))
    }
    @discardableResult
    public func addShaperImageURL(shaperProjectId: Int, url: String) async throws -> WSCreatedID {
        try await client.post("/api/shaper-projects/\(shaperProjectId)/images", body: KindURLBody(kind: "sketch", url: url))
    }
    @discardableResult
    public func uploadShaperImage(shaperProjectId: Int, file: MultipartFile) async throws -> WSCreatedID {
        try await client.postMultipart("/api/shaper-projects/\(shaperProjectId)/images",
                                       fields: ["kind": "sketch"], file: file)
    }
    @discardableResult
    public func addShaperCutItem(shaperProjectId: Int, _ item: CutListInput) async throws -> WSCreatedID {
        try await client.post("/api/shaper-projects/\(shaperProjectId)/cut-list", body: item)
    }

    // MARK: Build log

    /// Auth-exempt build-log photo URL (`?oid=` like images).
    public func buildLogImageURL(entryId: Int, userKey: String) -> URL {
        oidURL(path: "/api/build-log/\(entryId)/image", userKey: userKey)
    }
    /// Add a build-log entry with an optional photo (multipart `note` + `file?`).
    @discardableResult
    public func addBuildLogEntry(projectId: Int, note: String, file: MultipartFile? = nil) async throws -> BuildLogEntry {
        try await client.postMultipart("/api/projects/\(projectId)/build-log",
                                       fields: ["note": note], file: file)
    }
    public func deleteBuildLogEntry(id: Int) async throws {
        try await client.delete("/api/build-log/\(id)", as: EmptyResponse.self)
    }

    // MARK: Finish log

    @discardableResult
    public func addFinishLogEntry(projectId: Int, _ entry: FinishLogInput) async throws -> WSCreatedID {
        try await client.post("/api/projects/\(projectId)/finish-log", body: entry)
    }
    public func updateFinishLogEntry(id: Int, _ entry: FinishLogInput) async throws {
        try await client.put("/api/finish-log/\(id)", body: entry, as: EmptyResponse.self)
    }
    public func deleteFinishLogEntry(id: Int) async throws {
        try await client.delete("/api/finish-log/\(id)", as: EmptyResponse.self)
    }

    // MARK: Shopping list

    public func shoppingList() async throws -> [ShoppingItem] {
        try await client.get("/api/shopping-list")
    }

    // MARK: Project links

    public func addProjectLink(projectId: Int, linkedProjectId: Int, relationship: String) async throws {
        try await client.post("/api/projects/\(projectId)/links",
                              body: LinkBody(linkedProjectId: linkedProjectId, relationship: relationship), as: EmptyResponse.self)
    }
    public func removeProjectLink(id: Int) async throws {
        try await client.delete("/api/project-links/\(id)", as: EmptyResponse.self)
    }

    // MARK: Templates

    public func listTemplates() async throws -> [WSTemplate] {
        try await client.get("/api/templates")
    }
    @discardableResult
    public func saveAsTemplate(projectId: Int, name: String) async throws -> WSTemplate {
        try await client.post("/api/projects/\(projectId)/save-as-template", body: TemplateNameBody(templateName: name))
    }
    @discardableResult
    public func cloneTemplate(templateId: Int, title: String? = nil) async throws -> WSProject {
        try await client.post("/api/templates/\(templateId)/clone", body: TitleBody(title: title))
    }
    public func deleteTemplate(id: Int) async throws {
        try await client.delete("/api/templates/\(id)", as: EmptyResponse.self)
    }

    // MARK: Helpers

    private func oidURL(path: String, userKey: String) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "oid", value: userKey)]
        return comps?.url ?? baseURL
    }

    // Request-body shapes (encoded snake_case unless noted).
    private struct URLBody: Encodable { let url: String }
    private struct KindURLBody: Encodable { let kind: String; let url: String }
    private struct PurchasedBody: Encodable { let purchased: Bool }
    private struct LinkBody: Encodable { let linkedProjectId: Int; let relationship: String }
    private struct TemplateNameBody: Encodable { let templateName: String }
    private struct TitleBody: Encodable { let title: String? }
    private struct CutPlanConfigResponse: Decodable { let config: CutPlanConfig? }
}

/// Decodes the `{ "id": N }` responses returned by create endpoints for cut-list
/// rows, materials, images, finish-log, and shaper attachments.
public struct WSCreatedID: Decodable, Sendable, Identifiable {
    public let id: Int
}
