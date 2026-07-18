#if os(iOS)
import ActivityKit
import Foundation

/// Shared definition for the Exam Sandbox Live Activity (lock screen + Dynamic
/// Island). The app starts/ends it; the widget extension renders it. iOS-only —
/// guarded so NintekKit still builds on macOS.
public struct ExamActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var endDate: Date
        public var total: Int
        public init(endDate: Date, total: Int) {
            self.endDate = endDate
            self.total = total
        }
    }

    public var examCode: String
    public init(examCode: String) {
        self.examCode = examCode
    }
}
#endif
