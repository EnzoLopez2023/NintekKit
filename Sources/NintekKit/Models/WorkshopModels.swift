import Foundation

// Workshop API models — mirror the Express/SQLite backend (woodworking project
// journal). The server returns raw SQLite column names (snake_case), so
// `WorkshopAPI` decodes with `.convertFromSnakeCase` and these use camelCase.
//
// Decoder gotchas baked in here (from server.js):
//  • Dimensions (length/width/thickness) are STRINGS ("27 1/2", "1' 11½") — the
//    optimizer parses them later; never Double.
//  • `wood_types`/`tools_needed` arrive already hydrated as arrays.
//  • `purchased` is normalised to a real Bool by the server (both the detail and
//    shopping-list handlers do `!!m.purchased`).
//  • Create/Update return a BARE project row (no parts_count/total_cost/hero
//    aggregates, no nested arrays) — so those aggregate fields are OPTIONAL on
//    `WSProject`, and the fat detail is a separate `WSProjectDetail`.
//  • Most columns are nullable → optional.
//
// The cut-plan-config is the one exception to snake_case (see `CutPlanConfig`).

// MARK: - Enums

/// Project lifecycle. Server stores lowercase/underscore values; kept as a
/// String-backed enum with an `.unknown` fallback for resilience.
public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    case idea, planning
    case inProgress = "in_progress"
    case completed
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProjectStatus(rawValue: raw) ?? .unknown
    }

    public var label: String {
        switch self {
        case .idea: return "Idea"
        case .planning: return "Planning"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .unknown: return "Unknown"
        }
    }
}

public enum Difficulty: String, Codable, Sendable, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Difficulty(rawValue: raw) ?? .unknown
    }
}

public enum ImageKind: String, Codable, Sendable {
    case sketch, inspiration
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ImageKind(rawValue: raw) ?? .unknown
    }
}

// MARK: - Project (list row + bare create/update response)

/// A project as returned by `GET /api/projects` (list) and by create/update
/// (bare row). The aggregate columns are only present on the list query, so they
/// are optional here — the fat per-id payload is `WSProjectDetail`.
public struct WSProject: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public var description: String?
    public var sourceUrl: String?
    public var cutPlanUrl: String?
    public let status: ProjectStatus
    public let difficulty: Difficulty
    public let estimatedHours: Int
    public let woodTypes: [String]
    public let toolsNeeded: [String]
    public let createdAt: String
    public let updatedAt: String

    // Aggregates — present only on the list query (absent on create/update).
    public var partsCount: Int?
    public var totalCost: Double?
    public var heroImageId: Int?
    public var cutListNames: String?
    public var materialNames: String?
}

/// The fat detail aggregate (`GET /api/projects/:id`): the project plus every
/// related collection assembled server-side.
public struct WSProjectDetail: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public var description: String?
    public var sourceUrl: String?
    public var cutPlanUrl: String?
    public let status: ProjectStatus
    public let difficulty: Difficulty
    public let estimatedHours: Int
    public let woodTypes: [String]
    public let toolsNeeded: [String]
    public let images: [WSImage]
    public let cutList: [CutListItem]
    public let materials: [WSMaterial]
    public let totalCost: Double
    public let partsCount: Int
    public let buildLog: [BuildLogEntry]
    public let finishLog: [FinishLogEntry]
    public let links: [ProjectLink]
    public let createdAt: String
    public let updatedAt: String
}

/// One image (sketch or inspiration). Bytes are fetched separately from
/// `/api/images/:id?oid=<userKey>` — this row only carries metadata. PDFs are
/// allowed (`imageType == "application/pdf"`).
public struct WSImage: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public var projectId: Int?
    public var shaperProjectId: Int?
    public let kind: ImageKind
    public var imageType: String?
    public var imageUrl: String?
    public let sortOrder: Int

    public var isPDF: Bool { imageType == "application/pdf" }
}

/// A cut-list row. Dimensions are free-text strings ("27 1/2", "1' 11½"), parsed
/// only by the optimizer. Belongs to either a project or a shaper project.
public struct CutListItem: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public var projectId: Int?
    public let partName: String
    public let qty: Int
    public var length: String?
    public var width: String?
    public var thickness: String?
    public var material: String?
    public let sortOrder: Int
}

/// A material line. `purchased` is a real Bool (server normalises 0/1).
public struct WSMaterial: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let projectId: Int
    public let name: String
    public var qtyLabel: String?
    public let cost: Double
    public let purchased: Bool
    public let sortOrder: Int
}

/// A build-log entry (`build_log`). `filePath` is the on-disk photo name; fetch
/// its bytes from `/api/build-log/:id/image?oid=<userKey>`.
public struct BuildLogEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let projectId: Int
    public let note: String
    public var filePath: String?
    public var imageType: String?
    public let createdAt: String

    public var hasPhoto: Bool { filePath != nil }
}

/// A finish-log entry (`finish_log`).
public struct FinishLogEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public var projectId: Int?
    public let productName: String
    public var finishType: String?
    public var color: String?
    public var coats: Int?
    public var notes: String?
    public let appliedAt: String
}

/// A linked project relationship (`GET /api/projects/:id` → links).
public struct ProjectLink: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let relationship: String
    public let linkedId: Int
    public let linkedTitle: String
    public let linkedStatus: ProjectStatus
}

/// One row of `GET /api/shopping-list` — an unpurchased material joined with its
/// project title.
public struct ShoppingItem: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let projectId: Int
    public let name: String
    public var qtyLabel: String?
    public let cost: Double
    public let purchased: Bool
    public let sortOrder: Int
    public let projectTitle: String
}

/// A saved template (`GET /api/templates`).
public struct WSTemplate: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public var templateName: String?
    public var description: String?
    public let difficulty: Difficulty
    public let estimatedHours: Int
    public let woodTypes: [String]
    public let toolsNeeded: [String]
    public let partsCount: Int
    public var heroImageId: Int?
}

// MARK: - Shaper Hub projects

public struct ShaperMaterial: Codable, Sendable, Equatable {
    public let name: String
    public let qty: String
    public init(name: String, qty: String) { self.name = name; self.qty = qty }
}

/// A Shaper CNC project (`GET /api/shaper-projects[/:id]`). List and detail share
/// one shape; nested `images`/`cutList` are empty on the list query.
public struct ShaperProject: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let shaperUrl: String
    public var description: String?
    public var photoUrl: String?
    public let materials: [ShaperMaterial]
    public var instructions: String?
    public let images: [WSImage]
    public let cutList: [CutListItem]
    public var heroImageId: Int?
    public let createdAt: String
    public let updatedAt: String
}

// MARK: - Write payloads

/// Body for `POST`/`PUT /api/projects`. Encoded to snake_case by WorkshopAPI.
public struct ProjectInput: Codable, Sendable, Equatable {
    public var title: String
    public var description: String
    public var sourceUrl: String
    public var cutPlanUrl: String
    public var status: ProjectStatus
    public var difficulty: Difficulty
    public var estimatedHours: Int
    public var woodTypes: [String]
    public var toolsNeeded: [String]

    public init(title: String = "", description: String = "", sourceUrl: String = "",
                cutPlanUrl: String = "", status: ProjectStatus = .idea,
                difficulty: Difficulty = .intermediate, estimatedHours: Int = 0,
                woodTypes: [String] = [], toolsNeeded: [String] = []) {
        self.title = title; self.description = description; self.sourceUrl = sourceUrl
        self.cutPlanUrl = cutPlanUrl; self.status = status; self.difficulty = difficulty
        self.estimatedHours = estimatedHours; self.woodTypes = woodTypes; self.toolsNeeded = toolsNeeded
    }

    /// Prefill from an existing detail (edit form).
    public init(from d: WSProjectDetail) {
        title = d.title; description = d.description ?? ""; sourceUrl = d.sourceUrl ?? ""
        cutPlanUrl = d.cutPlanUrl ?? ""
        status = d.status == .unknown ? .idea : d.status
        difficulty = d.difficulty == .unknown ? .intermediate : d.difficulty
        estimatedHours = d.estimatedHours; woodTypes = d.woodTypes; toolsNeeded = d.toolsNeeded
    }
}

/// Body for a cut-list row create/update (fields optional; encoded snake_case).
public struct CutListInput: Codable, Sendable, Equatable {
    public var partName: String
    public var qty: Int
    public var length: String?
    public var width: String?
    public var thickness: String?
    public var material: String?
    public var sortOrder: Int?

    public init(partName: String = "", qty: Int = 1, length: String? = nil, width: String? = nil,
                thickness: String? = nil, material: String? = nil, sortOrder: Int? = nil) {
        self.partName = partName; self.qty = qty; self.length = length; self.width = width
        self.thickness = thickness; self.material = material; self.sortOrder = sortOrder
    }
}

/// Body for a material row create/update.
public struct MaterialInput: Codable, Sendable, Equatable {
    public var name: String
    public var qtyLabel: String?
    public var cost: Double
    public var purchased: Bool
    public var sortOrder: Int?

    public init(name: String = "", qtyLabel: String? = nil, cost: Double = 0,
                purchased: Bool = false, sortOrder: Int? = nil) {
        self.name = name; self.qtyLabel = qtyLabel; self.cost = cost
        self.purchased = purchased; self.sortOrder = sortOrder
    }
}

/// Body for a finish-log create/update (`applied_at` optional on create).
public struct FinishLogInput: Codable, Sendable, Equatable {
    public var productName: String
    public var finishType: String?
    public var color: String?
    public var coats: Int?
    public var notes: String?
    public var appliedAt: String?

    public init(productName: String = "", finishType: String? = nil, color: String? = nil,
                coats: Int? = nil, notes: String? = nil, appliedAt: String? = nil) {
        self.productName = productName; self.finishType = finishType; self.color = color
        self.coats = coats; self.notes = notes; self.appliedAt = appliedAt
    }
}

/// Body for `POST`/`PUT /api/shaper-projects`.
public struct ShaperProjectInput: Codable, Sendable, Equatable {
    public var title: String
    public var shaperUrl: String
    public var description: String?
    public var photoUrl: String?
    public var materials: [ShaperMaterial]
    public var instructions: String?

    public init(title: String = "", shaperUrl: String = "", description: String? = nil,
                photoUrl: String? = nil, materials: [ShaperMaterial] = [], instructions: String? = nil) {
        self.title = title; self.shaperUrl = shaperUrl; self.description = description
        self.photoUrl = photoUrl; self.materials = materials; self.instructions = instructions
    }
}

// MARK: - AI analyze results

/// `POST /api/projects/analyze-url` — suggested fields to prefill the form.
public struct AnalyzedProject: Codable, Sendable, Equatable {
    public struct CutRow: Codable, Sendable, Equatable {
        public let partName: String
        public let qty: Int
        public var length: String?
        public var width: String?
        public var thickness: String?
        public var material: String?
    }
    public struct MaterialRow: Codable, Sendable, Equatable {
        public let name: String
        public var qtyLabel: String?
    }
    public let title: String
    public let description: String
    public let difficulty: Difficulty
    public let estimatedHours: Int
    public let woodTypes: [String]
    public let toolsNeeded: [String]
    public let cutList: [CutRow]
    public let materials: [MaterialRow]
}

/// `POST /api/shaper-projects/analyze-url`.
public struct ShaperAnalysisResult: Codable, Sendable, Equatable {
    public let title: String
    public let description: String
    public let photoUrl: String
    public let materials: [ShaperMaterial]
    public let instructions: String
    public var imageUrls: [String]?
}

// MARK: - Cut-plan config (camelCase — NOT snake_case)

/// The optimizer's saved stock/kerf config. Stored as opaque JSON by the server
/// (`GET/PUT /api/projects/:id/cut-plan-config`) and shared verbatim with the web
/// app, whose keys are **camelCase** (`stockRows`, `lengthStr`, `kerfStr`). So
/// this type is coded WITHOUT the snake_case strategy (WorkshopAPI uses a plain
/// coder for these two endpoints) to keep web↔native configs interoperable.
public struct StockRow: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var lengthStr: String
    public var widthStr: String
    public var thicknessStr: String
    public var qtyStr: String
    public var label: String

    public init(id: String = UUID().uuidString, lengthStr: String = "", widthStr: String = "",
                thicknessStr: String = "", qtyStr: String = "1", label: String = "") {
        self.id = id; self.lengthStr = lengthStr; self.widthStr = widthStr
        self.thicknessStr = thicknessStr; self.qtyStr = qtyStr; self.label = label
    }
}

public struct CutPlanConfig: Codable, Sendable, Equatable {
    public var stockRows: [StockRow]
    public var kerfStr: String

    public init(stockRows: [StockRow] = [StockRow()], kerfStr: String = "0.125") {
        self.stockRows = stockRows; self.kerfStr = kerfStr
    }
}
