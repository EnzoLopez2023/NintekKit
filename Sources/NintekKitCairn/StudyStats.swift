import Foundation

// Comprehensive per-exam study stats aggregated from Cairn's local progress
// keys, matching the web-authored content semantics:
//   exam-prep-completed:<id>    → array of completed section ids
//   exam-prep-drill-stats:<id>  → { questionId: DrillQuestionStat }
//   exam-prep-analytics:<id>    → [SandboxAttempt] (local sandbox history)

public struct SubdomainBreakdown: Sendable, Equatable, Identifiable {
    public var id: String { subdomain }
    public let subdomain: String
    public let attempted: Int
    public let correct: Int
    public var accuracy: Double { attempted == 0 ? 0 : Double(correct) / Double(attempted) }
}

public struct ExamDetail: Sendable, Identifiable, Equatable {
    public var id: String { examId }
    public let examId: String
    public let examCode: String
    public let examTitle: String
    public let sectionsComplete: Int
    public let questionsAnswered: Int        // total drill answer events
    public let drillAccuracy: Double?        // 0…1
    public let attemptsCount: Int
    public let bestScaledScore: Int?         // /1000, from local analytics
    public let lastActivityAt: Int?          // epoch ms
    public let subdomains: [SubdomainBreakdown]   // weakest first

    public var lastActivity: Date? { lastActivityAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
    public var touched: Bool { sectionsComplete > 0 || questionsAnswered > 0 || attemptsCount > 0 }
}

public struct DetailedStats: Sendable, Equatable {
    public let exams: [ExamDetail]           // active only, most-recent activity first
    public let totalSectionsComplete: Int
    public let totalQuestionsAnswered: Int
    public let totalExamsTouched: Int
    public let bestScaledScore: Int?

    public init(exams: [ExamDetail], totalSectionsComplete: Int, totalQuestionsAnswered: Int,
                totalExamsTouched: Int, bestScaledScore: Int?) {
        self.exams = exams
        self.totalSectionsComplete = totalSectionsComplete
        self.totalQuestionsAnswered = totalQuestionsAnswered
        self.totalExamsTouched = totalExamsTouched
        self.bestScaledScore = bestScaledScore
    }

    public static let empty = DetailedStats(
        exams: [], totalSectionsComplete: 0, totalQuestionsAnswered: 0, totalExamsTouched: 0, bestScaledScore: nil)
}

// Decodable shapes for the local analytics key.
private struct SandboxPerQuestion: Decodable { let correct: Bool; let subdomain: String }
private struct SandboxAttempt: Decodable {
    let completedAt: Int
    let scoreScaled: Int
    let perQuestion: [SandboxPerQuestion]
}

public enum StudyStats {
    static let completedPrefix = "exam-prep-completed:"
    static let drillPrefix = "exam-prep-drill-stats:"
    static let analyticsPrefix = "exam-prep-analytics:"

    /// Aggregate the synced progress into per-exam detail, matching the web.
    public static func build(progress rows: [ProgressEntry], catalog: [ExamMeta]) -> DetailedStats {
        // Index rows by storage key for O(1) lookup.
        let byKey = Dictionary(rows.map { ($0.storageKey, $0.data) }, uniquingKeysWith: { a, _ in a })

        func decode<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
            guard let raw = byKey[key], let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }

        var details: [ExamDetail] = []
        var totalSections = 0, totalAnswered = 0, touchedCount = 0
        var overallBest: Int?

        for exam in catalog where exam.isActive {
            let id = exam.id
            let completed = decode(completedPrefix + id, [String].self) ?? []
            let drill = decode(drillPrefix + id, [String: DrillQuestionStat].self) ?? [:]
            let attempts = decode(analyticsPrefix + id, [SandboxAttempt].self) ?? []

            // Drill aggregates
            var answers = 0, correct = 0, lastDrill = 0
            for q in drill.values where q.attempts > 0 {
                answers += q.attempts
                correct += q.correct
                lastDrill = max(lastDrill, q.lastSeenAt)
            }
            let drillAccuracy = answers > 0 ? Double(correct) / Double(answers) : nil

            // Sandbox aggregates (local analytics)
            var best: Int?
            var lastAttempt = 0
            var subAgg: [String: (correct: Int, attempted: Int)] = [:]
            for a in attempts {
                best = max(best ?? Int.min, a.scoreScaled)
                lastAttempt = max(lastAttempt, a.completedAt)
                for pq in a.perQuestion {
                    var s = subAgg[pq.subdomain] ?? (0, 0)
                    s.attempted += 1
                    if pq.correct { s.correct += 1 }
                    subAgg[pq.subdomain] = s
                }
            }
            let subdomains = subAgg
                .map { SubdomainBreakdown(subdomain: $0.key, attempted: $0.value.attempted, correct: $0.value.correct) }
                .sorted { $0.accuracy < $1.accuracy }

            let lastActivity = max(lastDrill, lastAttempt)
            let detail = ExamDetail(
                examId: id, examCode: exam.code, examTitle: exam.title,
                sectionsComplete: completed.count,
                questionsAnswered: answers,
                drillAccuracy: drillAccuracy,
                attemptsCount: attempts.count,
                bestScaledScore: best,
                lastActivityAt: lastActivity > 0 ? lastActivity : nil,
                subdomains: subdomains
            )
            details.append(detail)

            totalSections += completed.count
            totalAnswered += answers
            if detail.touched { touchedCount += 1 }
            if let b = best { overallBest = max(overallBest ?? Int.min, b) }
        }

        details.sort { ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) }

        return DetailedStats(
            exams: details,
            totalSectionsComplete: totalSections,
            totalQuestionsAnswered: totalAnswered,
            totalExamsTouched: touchedCount,
            bestScaledScore: overallBest
        )
    }
}
