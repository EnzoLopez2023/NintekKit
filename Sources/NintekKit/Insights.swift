import Foundation

/// AI study insights from `POST /api/exam-prep/insights` (server proxies Claude,
/// caches 1h). Mirrors the web app's DetailsPage.
public struct Insights: Decodable, Sendable, Equatable {
    public struct Readiness: Decodable, Sendable, Equatable, Identifiable {
        public var id: String { examCode }
        public let examCode: String
        public let verdict: String        // "ready" | "close" | "needs work" | "just starting"
        public let etaHours: Int
        public let why: String
    }

    public let studyPlan: String          // newline-separated bullets
    public let readiness: [Readiness]
    public let nextStepNudge: String
    public let cached: Bool?

    public var studyPlanLines: [String] {
        studyPlan.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^[-•]\\s*", with: "", options: .regularExpression)
        }.filter { !$0.isEmpty }
    }
}

/// Compact stats payload for the insights request — the same projection the web
/// sends (`compactStatsForInsights`): only exams with activity, weak subdomains
/// only.
public struct InsightsPayload: Encodable, Sendable {
    public struct WeakSubdomain: Encodable, Sendable {
        public let name: String
        public let accuracy: Int
        public let attempted: Int
    }
    public struct ExamStat: Encodable, Sendable {
        public let code: String
        public let title: String
        public let sectionsComplete: Int
        public let questionsAnswered: Int
        public let drillAccuracy: Int?
        public let attempts: Int
        public let bestScaledScore: Int?
        public let weakSubdomains: [WeakSubdomain]
    }
    public struct Stats: Encodable, Sendable { public let exams: [ExamStat] }

    public let stats: Stats
    public let force: Bool

    /// Build the payload from ``DetailedStats`` — mirrors `compactStatsForInsights`.
    public init(from detailed: DetailedStats, force: Bool) {
        let exams = detailed.exams
            .filter { $0.sectionsComplete > 0 || $0.questionsAnswered > 0 || $0.attemptsCount > 0 }
            .map { e in
                ExamStat(
                    code: e.examCode, title: e.examTitle,
                    sectionsComplete: e.sectionsComplete,
                    questionsAnswered: e.questionsAnswered,
                    drillAccuracy: e.drillAccuracy.map { Int(($0 * 100).rounded()) },
                    attempts: e.attemptsCount,
                    bestScaledScore: e.bestScaledScore,
                    weakSubdomains: e.subdomains
                        .filter { $0.attempted >= 3 && $0.accuracy < 0.75 }
                        .prefix(5)
                        .map { WeakSubdomain(name: $0.subdomain, accuracy: Int(($0.accuracy * 100).rounded()), attempted: $0.attempted) }
                )
            }
        self.stats = Stats(exams: exams)
        self.force = force
    }
}
