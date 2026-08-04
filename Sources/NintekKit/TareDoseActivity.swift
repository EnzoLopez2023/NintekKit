import Foundation

#if os(iOS)
import ActivityKit

/// The Lock Screen and Dynamic Island presence on a dose day.
///
/// **Dose day, not dose week.** ActivityKit ends an activity after eight hours,
/// so a countdown to a weekly injection cannot live here — the activity would
/// expire six days before the thing it counts down to. What fits, and what the
/// user actually wants on the Lock Screen, is the last stretch: it starts a few
/// hours before the scheduled time and ends when the dose is logged or the day
/// is over.
///
/// The static half never changes for the life of the activity, which is what
/// lets the presentation render a medication and a strength without a single
/// update. `ContentState` carries only the one thing that can change — whether
/// it has been taken — because every field here costs an update to keep honest.
public struct TareDoseActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        /// `nil` while the dose is still outstanding.
        ///
        /// The countdown itself is deliberately **not** in here. `dueAt` is
        /// fixed and SwiftUI's `Text(timerInterval:)` ticks on its own, so a
        /// stored "minutes remaining" would be a value the app had to push a
        /// new update for every minute — and would be wrong in between.
        public var loggedAt: Date?

        public init(loggedAt: Date? = nil) {
            self.loggedAt = loggedAt
        }

        public var isLogged: Bool { loggedAt != nil }
    }

    /// Empty when the profile has no medication set, which the presentation
    /// renders as a plain "Dose" rather than a blank.
    public let medicationName: String
    /// Milligrams, unformatted. `0` when unknown — the presentation drops the
    /// strength line rather than printing "0 mg".
    public let doseMg: Double
    /// When the dose is scheduled. Fixed for the life of the activity.
    public let dueAt: Date

    public init(medicationName: String, doseMg: Double, dueAt: Date) {
        self.medicationName = medicationName
        self.doseMg = doseMg
        self.dueAt = dueAt
    }

    /// What the presentation prints as the title.
    public var displayName: String {
        TareDoseActivityWindow.displayName(medicationName)
    }

    /// `2.5 mg`, or `nil` when there is no strength to show.
    public var doseLabel: String? {
        TareDoseActivityWindow.doseLabel(doseMg)
    }
}
#endif

/// When a dose-day activity may run, and when it must stop.
///
/// Split out from the attributes so both the app that starts activities and the
/// tests that pin the window can reason about it without ActivityKit in the
/// way.
public enum TareDoseActivityWindow {
    /// How long before the scheduled time the activity appears.
    ///
    /// Four hours, against ActivityKit's eight-hour ceiling. That leaves four
    /// hours of *overdue* display, which is the half that matters — an activity
    /// that vanishes at the scheduled minute is useless to someone who was busy.
    public static let leadTime: TimeInterval = 4 * 3600

    /// How long after the scheduled time it stays.
    public static let trailTime: TimeInterval = 4 * 3600

    /// Whether an activity should be running for a dose due at `dueAt`.
    public static func isActive(dueAt: Date, now: Date = Date()) -> Bool {
        now >= dueAt.addingTimeInterval(-leadTime)
            && now <= dueAt.addingTimeInterval(trailTime)
    }

    /// When the system should dim the activity as out of date. Set to the end
    /// of the window so a phone that never wakes the app does not sit there
    /// showing a live countdown for a dose from yesterday.
    public static func staleDate(dueAt: Date) -> Date {
        dueAt.addingTimeInterval(trailTime)
    }

    /// When ActivityKit should dismiss it of its own accord.
    public static func dismissalDate(dueAt: Date) -> Date {
        dueAt.addingTimeInterval(trailTime)
    }
}

// MARK: Labels

extension TareDoseActivityWindow {
    /// The title, with a fallback for a profile that has no medication set.
    /// A blank line where a drug name belongs reads as a rendering failure.
    public static func displayName(_ medicationName: String) -> String {
        medicationName.isEmpty ? "Dose" : medicationName
    }

    /// `2.5 mg`, or `nil` when there is no strength to show.
    ///
    /// Absent rather than `0 mg`: zero is what the app stores when it does not
    /// know the prescription, and printing it would turn "unknown" into a claim
    /// about someone's dose on their Lock Screen.
    public static func doseLabel(_ doseMg: Double) -> String? {
        guard doseMg > 0 else { return nil }
        let rounded = (doseMg * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%g", rounded)
        return "\(text) mg"
    }
}
