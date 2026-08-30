import XCTest
@testable import NintekKitTare

/// The dose-day Live Activity's window and labels.
///
/// ActivityKit itself is untestable here — an `Activity` needs a real device and
/// a running app — so what is pinned is the part that decides *whether* an
/// activity should exist at all, plus the two strings the presentation renders
/// without asking anything else.
final class TareDoseActivityTests: XCTestCase {

    private let due = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Window

    /// The eight-hour ceiling is why this is a dose-*day* activity. A window
    /// wider than ActivityKit allows would be ended by the system mid-countdown,
    /// which looks identical to a bug.
    func testWindowFitsInsideActivityKitsEightHourLimit() {
        let total = TareDoseActivityWindow.leadTime + TareDoseActivityWindow.trailTime
        XCTAssertLessThanOrEqual(total, 8 * 3600)
    }

    func testActivityRunsFromTheLeadTimeUntilTheTrailTime() {
        XCTAssertTrue(TareDoseActivityWindow.isActive(dueAt: due, now: due))
        XCTAssertTrue(TareDoseActivityWindow.isActive(
            dueAt: due, now: due.addingTimeInterval(-TareDoseActivityWindow.leadTime)))
        XCTAssertTrue(TareDoseActivityWindow.isActive(
            dueAt: due, now: due.addingTimeInterval(TareDoseActivityWindow.trailTime)))
    }

    func testActivityDoesNotRunOutsideTheWindow() {
        XCTAssertFalse(TareDoseActivityWindow.isActive(
            dueAt: due, now: due.addingTimeInterval(-TareDoseActivityWindow.leadTime - 1)))
        XCTAssertFalse(TareDoseActivityWindow.isActive(
            dueAt: due, now: due.addingTimeInterval(TareDoseActivityWindow.trailTime + 1)))
    }

    /// The overdue half is the half that matters. An activity that disappeared
    /// at the scheduled minute would be gone precisely when someone who was busy
    /// needs the reminder.
    func testOverdueTimeIsNotShorterThanTheCountdown() {
        XCTAssertGreaterThanOrEqual(TareDoseActivityWindow.trailTime,
                                    TareDoseActivityWindow.leadTime)
    }

    func testStaleAndDismissalLandAtTheEndOfTheWindow() {
        let end = due.addingTimeInterval(TareDoseActivityWindow.trailTime)
        XCTAssertEqual(TareDoseActivityWindow.staleDate(dueAt: due), end)
        XCTAssertEqual(TareDoseActivityWindow.dismissalDate(dueAt: due), end)
    }

    // MARK: Labels

    func testDisplayNameFallsBackWhenNoMedicationIsSet() {
        XCTAssertEqual(TareDoseActivityWindow.displayName("Zepbound"), "Zepbound")
        XCTAssertEqual(TareDoseActivityWindow.displayName(""), "Dose")
    }

    /// A missing strength drops the line. Printing "0 mg" would be a claim about
    /// the prescription rather than an admission that it is unknown.
    func testDoseLabelIsAbsentRatherThanZero() {
        XCTAssertNil(TareDoseActivityWindow.doseLabel(0))
        XCTAssertNil(TareDoseActivityWindow.doseLabel(-1))
    }

    func testDoseLabelDropsATrailingZero() {
        XCTAssertEqual(TareDoseActivityWindow.doseLabel(5), "5 mg")
        XCTAssertEqual(TareDoseActivityWindow.doseLabel(2.5), "2.5 mg")
        XCTAssertEqual(TareDoseActivityWindow.doseLabel(0.25), "0.25 mg")
    }

    // MARK: State

    /// ActivityKit only exists on iOS, so the attributes themselves can only be
    /// exercised there. The window and the labels above are deliberately plain
    /// Foundation so they run on every platform the package supports.
    #if os(iOS)
    func testStateStartsOutstandingAndRoundTrips() throws {
        let pending = TareDoseActivityAttributes.ContentState()
        XCTAssertFalse(pending.isLogged)

        let taken = TareDoseActivityAttributes.ContentState(loggedAt: due)
        XCTAssertTrue(taken.isLogged)

        let data = try JSONEncoder().encode(taken)
        let back = try JSONDecoder().decode(
            TareDoseActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(back, taken)
    }

    func testAttributesDelegateToTheSharedLabels() {
        let a = TareDoseActivityAttributes(medicationName: "", doseMg: 2.5, dueAt: due)
        XCTAssertEqual(a.displayName, "Dose")
        XCTAssertEqual(a.doseLabel, "2.5 mg")
    }
    #endif
}
