import XCTest
@testable import NintekKit

/// Tests for the phone ⇄ watch contract. `WCSession` itself is not exercised —
/// it needs a paired device — so what is proven here is the part that can break
/// silently: that a payload survives the round trip, and that the wrist refuses
/// the same values the phone would.
final class TareWatchLinkTests: XCTestCase {

    // MARK: Codable

    func testEntryRoundTripsThroughThePayloadDictionary() throws {
        let original = TareWatchLogEntry(
            kind: .glucose, value: 104, recordedAt: Date(timeIntervalSince1970: 1_770_000_000),
            detail: "fasting")

        let dict = TareWatchPayload.encode(original)
        let decoded = TareWatchPayload.decodeEntry(dict[TareWatchPayload.entryKey])

        XCTAssertEqual(decoded, original)
    }

    func testSnapshotRoundTripsThroughThePayloadDictionary() throws {
        let dict = TareWatchPayload.encode(TareWidgetSnapshot.sample)
        let decoded = TareWatchPayload.decodeSnapshot(dict[TareWatchPayload.snapshotKey])

        XCTAssertEqual(decoded, TareWidgetSnapshot.sample)
    }

    /// The keys are what the two processes agree on; a rename on one side only
    /// produces a link that connects and delivers nothing.
    func testEachDirectionUsesItsOwnKey() {
        XCTAssertNotEqual(TareWatchPayload.snapshotKey, TareWatchPayload.entryKey)
        XCTAssertNotNil(TareWatchPayload.encode(TareWidgetSnapshot.sample)[TareWatchPayload.snapshotKey])
        XCTAssertNotNil(TareWatchPayload.encode(
            TareWatchLogEntry(kind: .mood, value: 7))[TareWatchPayload.entryKey])
    }

    func testDecodingGarbageYieldsNilRatherThanThrowing() {
        let junk = Data("not json".utf8)
        XCTAssertNil(TareWatchPayload.decodeEntry(junk))
        XCTAssertNil(TareWatchPayload.decodeSnapshot(junk))
        XCTAssertNil(TareWatchPayload.decodeEntry(nil))
        XCTAssertNil(TareWatchPayload.decodeSnapshot(nil))
    }

    /// A snapshot decoded as an entry is the shape mismatch a mis-keyed
    /// dictionary would produce, and it must not half-succeed.
    func testASnapshotDoesNotDecodeAsAnEntry() throws {
        let data = try XCTUnwrap(TareWatchPayload.encode(TareWidgetSnapshot.sample)[TareWatchPayload.snapshotKey])
        XCTAssertNil(TareWatchPayload.decodeEntry(data))
    }

    // MARK: Identity

    /// Two entries logged with the same value are still two entries. The id is
    /// what stops a redelivered transfer becoming a second reading, so it must
    /// not be derived from the contents.
    func testEntriesGetDistinctIdentifiersByDefault() {
        let a = TareWatchLogEntry(kind: .weight, value: 212)
        let b = TareWatchLogEntry(kind: .weight, value: 212)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testAnExplicitIdentifierSurvivesTheRoundTrip() throws {
        let entry = TareWatchLogEntry(id: "fixed-id", kind: .dose, value: 7.5, detail: "Ozempic")
        let dict = TareWatchPayload.encode(entry)
        XCTAssertEqual(TareWatchPayload.decodeEntry(dict[TareWatchPayload.entryKey])?.id, "fixed-id")
    }

    // MARK: Validation

    func testGlucoseBoundsMatchTheAppsOwn() {
        XCTAssertTrue(TareWatchLogEntry(kind: .glucose, value: 20).isValid)
        XCTAssertTrue(TareWatchLogEntry(kind: .glucose, value: 600).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .glucose, value: 19).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .glucose, value: 601).isValid)
    }

    func testWeightBoundsMatchTheAppsOwn() {
        XCTAssertTrue(TareWatchLogEntry(kind: .weight, value: 50).isValid)
        XCTAssertTrue(TareWatchLogEntry(kind: .weight, value: 600).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .weight, value: 49).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .weight, value: 601).isValid)
    }

    /// The wellbeing scale is 1–10 integers. A 7.5 mood is not a mood the form
    /// can produce, and it would land in the store as a truncated 7.
    func testMoodMustBeAWholeNumberInScale() {
        XCTAssertTrue(TareWatchLogEntry(kind: .mood, value: 1).isValid)
        XCTAssertTrue(TareWatchLogEntry(kind: .mood, value: 10).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .mood, value: 0).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .mood, value: 11).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .mood, value: 7.5).isValid)
    }

    func testADoseMustBePositive() {
        XCTAssertTrue(TareWatchLogEntry(kind: .dose, value: 0.25).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .dose, value: 0).isValid)
        XCTAssertFalse(TareWatchLogEntry(kind: .dose, value: -1).isValid)
    }
}
