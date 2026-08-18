import Foundation

// Legacy API DTOs remain in the aggregate module for source compatibility.

/// One graded question inside a legacy attempt response.
public struct QuestionResult: Codable, Identifiable, Sendable, Equatable {
    public var id: String { questionId }
    public let questionId: String
    public let selected: String
    public let correct: Int

    public var isCorrect: Bool { correct == 1 }
}

/// A legacy attempt response plus its per-question results.
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

/// A legacy response from recording an attempt.
public struct AttemptCreated: Decodable, Sendable {
    public let id: Int
    public let score: Int
}
