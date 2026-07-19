import Foundation

/// A completed exam attempt. Previously one row of `GET /api/exam-prep/attempts`;
/// now built from the local SwiftData/CloudKit store. `id` is a stable UUID
/// string (CloudKit records have no server autoincrement). `passed` is kept as
/// 0/1 so ``isPassed`` and existing UI stay unchanged.
public struct ExamAttempt: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let mode: String
    public let score: Int
    public let totalQuestions: Int
    public let correctCount: Int
    public let domain1Score: Int
    public let domain1Total: Int
    public let domain2Score: Int
    public let domain2Total: Int
    public let passed: Int
    public let timeSpentSec: Int?
    public let completedAt: String

    public var isPassed: Bool { passed == 1 }

    public init(
        id: String, mode: String, score: Int, totalQuestions: Int, correctCount: Int,
        domain1Score: Int, domain1Total: Int, domain2Score: Int, domain2Total: Int,
        passed: Int, timeSpentSec: Int?, completedAt: String
    ) {
        self.id = id; self.mode = mode; self.score = score
        self.totalQuestions = totalQuestions; self.correctCount = correctCount
        self.domain1Score = domain1Score; self.domain1Total = domain1Total
        self.domain2Score = domain2Score; self.domain2Total = domain2Total
        self.passed = passed; self.timeSpentSec = timeSpentSec; self.completedAt = completedAt
    }
}

/// One graded question inside an attempt (`GET /api/exam-prep/attempts/:id`).
public struct QuestionResult: Codable, Identifiable, Sendable, Equatable {
    public var id: String { questionId }
    public let questionId: String
    public let selected: String
    public let correct: Int

    public var isCorrect: Bool { correct == 1 }
}

/// A single attempt plus its per-question results.
public struct AttemptDetail: Codable, Sendable, Equatable {
    public let id: Int
    public let mode: String
    public let score: Int
    public let totalQuestions: Int
    public let correctCount: Int
    public let domain1Score: Int
    public let domain1Total: Int
    public let domain2Score: Int
    public let domain2Total: Int
    public let passed: Int
    public let timeSpentSec: Int?
    public let completedAt: String
    public let results: [QuestionResult]

    public var isPassed: Bool { passed == 1 }
}

/// Body for `POST /api/exam-prep/attempts` — records a completed exam so it
/// shows in the user's activity/attempts history.
public struct NewAttempt: Encodable, Sendable {
    public struct Result: Encodable, Sendable {
        public let questionId: String
        public let selected: [Int]
        public let correct: Bool
        public init(questionId: String, selected: [Int], correct: Bool) {
            self.questionId = questionId; self.selected = selected; self.correct = correct
        }
    }

    public let mode: String
    public let score: Int
    public let totalQuestions: Int
    public let correctCount: Int
    public let domain1Score: Int
    public let domain1Total: Int
    public let domain2Score: Int
    public let domain2Total: Int
    public let passed: Bool
    public let timeSpentSec: Int?
    public let results: [Result]

    public init(mode: String, score: Int, totalQuestions: Int, correctCount: Int,
                passed: Bool, timeSpentSec: Int?, results: [Result],
                domain1Score: Int = 0, domain1Total: Int = 0,
                domain2Score: Int = 0, domain2Total: Int = 0) {
        self.mode = mode; self.score = score; self.totalQuestions = totalQuestions
        self.correctCount = correctCount; self.passed = passed; self.timeSpentSec = timeSpentSec
        self.results = results; self.domain1Score = domain1Score; self.domain1Total = domain1Total
        self.domain2Score = domain2Score; self.domain2Total = domain2Total
    }
}

/// Response from recording an attempt.
public struct AttemptCreated: Decodable, Sendable {
    public let id: Int
    public let score: Int
}

/// A frequently-missed question (`GET /api/exam-prep/stats` → weakAreas).
public struct WeakArea: Codable, Sendable, Identifiable, Equatable {
    public var id: String { questionId }
    public let questionId: String
    public let attempts: Int
    public let wrongCount: Int
    public var wrongRate: Double { attempts == 0 ? 0 : Double(wrongCount) / Double(attempts) }

    public init(questionId: String, attempts: Int, wrongCount: Int) {
        self.questionId = questionId
        self.attempts = attempts
        self.wrongCount = wrongCount
    }
}

/// Aggregate exam-attempt statistics for the signed-in user. Nullable fields
/// come back `null` when there are no attempts yet.
public struct ExamStats: Codable, Sendable, Equatable {
    public let totalAttempts: Int
    public let passedAttempts: Int?
    public let bestScore: Int?
    public let avgScore: Double?
    public let avgTime: Double?
    public let weakAreas: [WeakArea]

    public var hasAttempts: Bool { totalAttempts > 0 }

    public init(totalAttempts: Int, passedAttempts: Int?, bestScore: Int?,
                avgScore: Double?, avgTime: Double?, weakAreas: [WeakArea]) {
        self.totalAttempts = totalAttempts
        self.passedAttempts = passedAttempts
        self.bestScore = bestScore
        self.avgScore = avgScore
        self.avgTime = avgTime
        self.weakAreas = weakAreas
    }
}

/// One row of the synced key-value store (`GET /api/exam-prep/progress`). This
/// is the same `exam-prep-*` data the web app mirrors from localStorage; the
/// native app reads and writes it through the same endpoints so progress
/// follows the signed-in user across web and iOS.
public struct ProgressEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: String { storageKey }
    public let storageKey: String
    public let data: String
    public let updatedAt: Int

    public init(storageKey: String, data: String, updatedAt: Int) {
        self.storageKey = storageKey
        self.data = data
        self.updatedAt = updatedAt
    }
}
