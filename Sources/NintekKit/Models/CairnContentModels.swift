import Foundation

// Exam content, served by the backend content API (extracted from the web
// frontend). Field names match the JSON exactly.

/// One exam in the catalog (`GET /api/exam-prep/catalog`).
public struct ExamMeta: Codable, Identifiable, Sendable, Equatable {
    public struct Domain: Codable, Sendable, Equatable {
        public let label: String
        public let weight: String
    }

    public let id: String            // slug, e.g. "PL300"
    public let code: String          // public code, e.g. "PL-300"
    public let vendor: String
    public let title: String
    public let tagline: String
    public let status: String        // "active" | "coming-soon"
    public let level: String?
    public let domains: [Domain]?
    public let durationMin: Int?
    public let passScore: Int?
    public let questionCount: Int?

    public var isActive: Bool { status == "active" }
}

/// A flashcard (`GET /api/exam-prep/exams/:id/flashcards`). `front`/`back` are
/// Markdown strings.
public struct Flashcard: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let front: String
    public let back: String
    public let topic: String
}

/// A glossary term (`GET /api/exam-prep/exams/:id/glossary`).
public struct GlossaryEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: String { term }
    public let term: String
    public let definition: String
}

// MARK: - Questions

public struct MatchData: Codable, Sendable, Equatable {
    public let leftItems: [String]
    public let rightItems: [String]
    public let correctPairs: [[Int]]
}

public struct HotAreaTarget: Codable, Sendable, Equatable {
    public let id: String
    public let label: String
}

public struct HotAreaData: Codable, Sendable, Equatable {
    public let svg: String
    public let targets: [HotAreaTarget]
    public let correctTargetIds: [String]
    public let selectAll: Bool?
}

public struct CaseSubQuestion: Codable, Sendable, Equatable {
    public let question: String
    public let type: String
    public let options: [String]
    public let correctAnswers: [Int]
    public let explanation: String
}

public struct CaseStudyData: Codable, Sendable, Equatable {
    public let scenario: String
    public let subQuestions: [CaseSubQuestion]
}

/// A practice/exam question (`GET /api/exam-prep/exams/:id/questions`). `type`
/// and `difficulty` are kept as strings so an unrecognized value from newer
/// content never fails decoding; ``QuestionKind`` exposes a typed view.
public struct Question: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let domain: Int
    public let subdomain: String
    public let type: String
    public let difficulty: String
    public let question: String
    public let options: [String]
    public let correctAnswers: [Int]
    public let explanation: String
    public let examTip: String?
    public let codeSnippet: String?
    public let match: MatchData?
    public let hotArea: HotAreaData?
    public let caseStudy: CaseStudyData?

    public var kind: QuestionKind { QuestionKind(rawValue: type) ?? .unknown }
}

public enum QuestionKind: String, Sendable {
    case single, multi, ordering, yesno, match
    case hotArea = "hot-area"
    case caseStudy = "case-study"
    case unknown
}
