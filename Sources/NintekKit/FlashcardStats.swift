import Foundation

/// SM-2 spaced-repetition state for one flashcard. Field names + semantics match
/// the web app's `FlashcardStat` exactly so the two clients read and write the
/// same synced `exam-prep-flashcard-stats:<examId>` progress key.
public struct FlashcardStat: Codable, Sendable, Equatable {
    public let cardId: String
    public var reviews: Int
    public var interval: Int        // days until next review
    public var ease: Double         // 0.1…1.0
    public var nextReviewAt: Int    // epoch ms
    public var lastReviewedAt: Int  // epoch ms

    public init(cardId: String, reviews: Int = 0, interval: Int = 0, ease: Double = 0.5,
                nextReviewAt: Int = 0, lastReviewedAt: Int = 0) {
        self.cardId = cardId; self.reviews = reviews; self.interval = interval
        self.ease = ease; self.nextReviewAt = nextReviewAt; self.lastReviewedAt = lastReviewedAt
    }
}

public enum FlashcardRating: String, Sendable, CaseIterable {
    case forgot
    case almost
    case gotIt = "got-it"
}

/// Map of cardId → stat, exactly as serialized in the progress store.
public typealias FlashcardStatsMap = [String: FlashcardStat]

/// The SM-2 engine, ported 1:1 from the web app's `recordFlashcardRating` so
/// intervals/ease evolve identically across web and iOS.
public enum FlashcardSM2 {
    static let dayMs = 86_400_000

    /// The synced progress key for an exam's flashcard stats.
    public static func storageKey(examId: String) -> String {
        "exam-prep-flashcard-stats:\(examId)"
    }

    public static func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    /// Apply a rating to `cardId`, returning an updated map. Pure — `now` is
    /// injectable for deterministic tests.
    public static func record(_ stats: FlashcardStatsMap, cardId: String,
                              rating: FlashcardRating, now: Int = FlashcardSM2.nowMs()) -> FlashcardStatsMap {
        let prev = stats[cardId] ?? FlashcardStat(cardId: cardId)
        var ease = prev.ease
        var interval = prev.interval

        switch rating {
        case .forgot:
            ease = max(0.1, ease * 0.7)
            interval = 1
        case .almost:
            ease = max(0.1, ease * 0.95)
            interval = max(1, Int((Double(max(1, interval)) * 1.5).rounded()))
        case .gotIt:
            ease = min(1.0, ease * 1.15)
            interval = max(2, Int((Double(max(1, interval)) * 3).rounded()))
        }
        interval = min(60, interval)

        var next = stats
        next[cardId] = FlashcardStat(
            cardId: cardId,
            reviews: prev.reviews + 1,
            interval: interval,
            ease: ease,
            nextReviewAt: now + interval * dayMs,
            lastReviewedAt: now
        )
        return next
    }

    /// Cards due now (never-reviewed or past their nextReviewAt), most-overdue
    /// first — matching the web app's queue ordering.
    public static func dueQueue<T: Identifiable>(_ cards: [T], stats: FlashcardStatsMap,
                                                 now: Int = FlashcardSM2.nowMs()) -> [T] where T.ID == String {
        cards
            .compactMap { card -> (card: T, overdue: Int)? in
                let st = stats[card.id]
                if let st, st.nextReviewAt > now { return nil }
                let overdue = stats[card.id].map { now - $0.nextReviewAt } ?? Int.max
                return (card, overdue)
            }
            .sorted { $0.overdue > $1.overdue }
            .map(\.card)
    }

    public static func masteredCount(_ stats: FlashcardStatsMap, masteredInterval: Int = 14) -> Int {
        stats.values.filter { $0.interval >= masteredInterval }.count
    }
}
