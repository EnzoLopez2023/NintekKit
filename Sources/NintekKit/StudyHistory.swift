import Foundation

/// One question's drill record, as stored in the synced `exam-prep-drill-stats:`
/// keys. Only the fields we need are decoded; the web app stores more (SM-2
/// state, confidence) which is ignored here.
public struct DrillQuestionStat: Codable, Sendable {
    public let questionId: String
    public let attempts: Int
    public let correct: Int
    public let lastSeenAt: Int   // epoch ms

    public init(questionId: String, attempts: Int, correct: Int, lastSeenAt: Int) {
        self.questionId = questionId
        self.attempts = attempts
        self.correct = correct
        self.lastSeenAt = lastSeenAt
    }
}

/// Aggregated study activity for one exam, derived from its drill stats.
public struct ExamActivity: Sendable, Identifiable, Equatable {
    public var id: String { examId }
    public let examId: String
    public let questionsSeen: Int
    public let attempts: Int
    public let correct: Int
    public let lastSeenAt: Int   // epoch ms

    public var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
    public var lastStudied: Date { Date(timeIntervalSince1970: Double(lastSeenAt) / 1000) }
}

/// Derives the user's real study history from the synced progress rows — the
/// drill activity the web app records as you answer practice questions.
public enum StudyHistory {
    static let drillPrefix = "exam-prep-drill-stats:"

    /// One `ExamActivity` per exam with drill activity, most-recent first.
    public static func activity(from rows: [ProgressEntry]) -> [ExamActivity] {
        rows.compactMap { row -> ExamActivity? in
            guard row.storageKey.hasPrefix(drillPrefix),
                  let data = row.data.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: DrillQuestionStat].self, from: data),
                  !map.isEmpty else { return nil }

            let examId = String(row.storageKey.dropFirst(drillPrefix.count))
            let attempts = map.values.reduce(0) { $0 + $1.attempts }
            let correct = map.values.reduce(0) { $0 + $1.correct }
            let last = map.values.map(\.lastSeenAt).max() ?? 0
            return ExamActivity(examId: examId, questionsSeen: map.count,
                                attempts: attempts, correct: correct, lastSeenAt: last)
        }
        .sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    /// Total distinct questions practiced across all exams.
    public static func totalQuestionsSeen(_ activity: [ExamActivity]) -> Int {
        activity.reduce(0) { $0 + $1.questionsSeen }
    }
}
