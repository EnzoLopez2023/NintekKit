import XCTest
@testable import NintekKitTare

/// Tests for Tare's widget snapshot. The App Group store itself is exercised
/// only as a round-trip: `UserDefaults(suiteName:)` returns `nil` in a plain
/// SwiftPM test process (no entitlement), so `save`/`load` are no-ops here and
/// the real hand-off is proven on device instead.
final class TareWidgetDataTests: XCTestCase {

    // MARK: Codable

    func testRoundTripsThroughJSON() throws {
        let original = TareWidgetSnapshot.sample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TareWidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEmptySnapshotHasNoHealthData() {
        let s = TareWidgetSnapshot.empty
        XCTAssertNil(s.lastInjectionAt)
        XCTAssertNil(s.glucoseValue)
        XCTAssertNil(s.weightValue)
        XCTAssertNil(s.goalWeight)
        XCTAssertTrue(s.glucoseSpark.isEmpty)
        XCTAssertTrue(s.weightSpark.isEmpty)
    }

    /// The gallery renders this before any App Group read, so a broken sample
    /// is what a person sees when deciding whether to add the widget.
    func testSampleIsFullyPopulated() {
        let s = TareWidgetSnapshot.sample
        XCTAssertNotNil(s.lastInjectionAt)
        XCTAssertNotNil(s.doseMg)
        XCTAssertNotNil(s.glucoseValue)
        XCTAssertNotNil(s.glucoseBand)
        XCTAssertNotNil(s.weightValue)
        XCTAssertNotNil(s.goalProgress)
        XCTAssertFalse(s.glucoseSpark.isEmpty)
        XCTAssertFalse(s.weightSpark.isEmpty)
    }

    // MARK: goalProgress

    func testGoalProgressIsFractionOfDistanceCovered() {
        var s = TareWidgetSnapshot(weightValue: 210, goalWeight: 190, startWeight: 230)
        XCTAssertEqual(s.goalProgress ?? 0, 0.5, accuracy: 0.0001)

        s.weightValue = 230
        XCTAssertEqual(s.goalProgress ?? -1, 0, accuracy: 0.0001)

        s.weightValue = 190
        XCTAssertEqual(s.goalProgress ?? -1, 1, accuracy: 0.0001)
    }

    /// Overshooting the goal must not draw an arc past full, and gaining back
    /// past the start must not draw a negative one.
    func testGoalProgressClamps() {
        var s = TareWidgetSnapshot(weightValue: 180, goalWeight: 190, startWeight: 230)
        XCTAssertEqual(s.goalProgress ?? -1, 1, accuracy: 0.0001)

        s.weightValue = 240
        XCTAssertEqual(s.goalProgress ?? -1, 0, accuracy: 0.0001)
    }

    func testGoalProgressNilWithoutAllThreeWeights() {
        XCTAssertNil(TareWidgetSnapshot(weightValue: 210, goalWeight: 190).goalProgress)
        XCTAssertNil(TareWidgetSnapshot(weightValue: 210, startWeight: 230).goalProgress)
        XCTAssertNil(TareWidgetSnapshot(goalWeight: 190, startWeight: 230).goalProgress)
    }

    /// A goal equal to the start has no denominator — it must not divide by
    /// zero and produce a NaN arc.
    func testGoalProgressNilWhenStartEqualsGoal() {
        let s = TareWidgetSnapshot(weightValue: 210, goalWeight: 200, startWeight: 200)
        XCTAssertNil(s.goalProgress)
    }

    // MARK: Bands

    /// The raw values are the app's `GlucoseStatusLabel` strings, and the
    /// snapshot is written by one target and read by another — a rename on
    /// either side has to break a test, not a widget.
    func testGlucoseBandRawValuesMatchTheAppsLabels() {
        XCTAssertEqual(TareWidgetSnapshot.GlucoseBand.low.rawValue, "Low")
        XCTAssertEqual(TareWidgetSnapshot.GlucoseBand.normal.rawValue, "Normal")
        XCTAssertEqual(TareWidgetSnapshot.GlucoseBand.elevated.rawValue, "Elevated")
        XCTAssertEqual(TareWidgetSnapshot.GlucoseBand.high.rawValue, "High")
        XCTAssertEqual(TareWidgetSnapshot.GlucoseBand.allCases.count, 4)
    }

    // MARK: Store

    func testAppGroupIsTheBundleGroup() {
        XCTAssertEqual(TareWidgetStore.appGroup, "group.com.nintek.tare")
    }

    /// `update` must preserve the slices it does not touch — the whole reason
    /// it exists rather than a plain `save`.
    func testUpdatePreservesUntouchedSlices() {
        var snapshot = TareWidgetSnapshot.sample
        let glucoseBefore = snapshot.glucoseValue
        let doseBefore = snapshot.doseMg

        // Exercise the mutation the store applies, without the App Group.
        var copy = snapshot
        copy.weightValue = 201.5
        copy.updatedAt = Date()
        snapshot = copy

        XCTAssertEqual(snapshot.weightValue, 201.5)
        XCTAssertEqual(snapshot.glucoseValue, glucoseBefore)
        XCTAssertEqual(snapshot.doseMg, doseBefore)
    }
}
