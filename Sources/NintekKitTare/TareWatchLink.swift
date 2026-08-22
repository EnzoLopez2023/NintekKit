import Foundation

/// One thing logged from the wrist, on its way to the phone.
///
/// The Watch app has no SwiftData store of its own. It cannot: the store is
/// pinned to the iPhone app's container (see `TareWidgetSnapshot`), CloudKit
/// would give the watch a second replica to reconcile, and a wrist app that
/// owns health records is a wrist app that can lose them. So the watch writes
/// nothing — it *describes* a write and hands it to the phone, which owns the
/// database and is the only thing that touches it.
///
/// Values cross in **canonical** units, not display units — the opposite
/// convention to `TareWidgetSnapshot`, and deliberately so. The snapshot flows
/// outward to be *rendered*, so it is pre-converted and the reader never has to
/// guess. This flows inward to be *stored*, and the store's units are fixed:
/// mg/dL, pounds, milligrams. Converting on the watch, where the display unit
/// is already known, means the phone never has to reconstruct which unit the
/// wrist happened to be showing at the time.
public struct TareWatchLogEntry: Codable, Sendable, Equatable, Identifiable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case glucose
        case weight
        case dose
        case mood
    }

    /// Stable across retries. `transferUserInfo` guarantees delivery but not
    /// exactly-once delivery — a phone that crashes between the write and the
    /// acknowledgement sees the same transfer again on relaunch. The phone
    /// remembers the ids it has already applied and drops repeats, so a glucose
    /// reading logged once on the wrist cannot land twice in the database.
    public var id: String
    public var kind: Kind

    /// mg/dL for `.glucose`, pounds for `.weight`, milligrams for `.dose`,
    /// 1…10 for `.mood`.
    public var value: Double

    /// When it happened, not when it synced. A reading logged in a tunnel and
    /// delivered an hour later belongs at the time it was taken.
    public var recordedAt: Date

    /// The glucose reading type for `.glucose`, the medication name for
    /// `.dose`. Unused by the other kinds.
    public var detail: String?

    public init(id: String = UUID().uuidString,
                kind: Kind,
                value: Double,
                recordedAt: Date = Date(),
                detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.value = value
        self.recordedAt = recordedAt
        self.detail = detail
    }

    /// The bounds the phone enforces before writing, expressed here so the
    /// wrist can refuse a bad value before spending a transfer on it. Same
    /// numbers as the app's own validation — a reading the phone would reject
    /// should never leave the watch looking like it was accepted.
    public var isValid: Bool {
        switch kind {
        case .glucose: (20...600).contains(value)
        case .weight: (50...600).contains(value)
        case .dose: value > 0 && value <= 100
        case .mood: (1...10).contains(value) && value == value.rounded()
        }
    }
}

/// Encodes both directions of the phone ⇄ watch conversation into the
/// dictionaries `WCSession` accepts.
///
/// `WCSession` takes `[String: Any]` and requires every value to be a property
/// list type. Rather than flatten the models into loose keys — where a field
/// added on one side and not the other fails silently at runtime — everything
/// crosses as a single JSON `Data` blob under one key. `Data` is a plist type,
/// `Codable` handles the versioning, and the dictionary stays `Sendable`, which
/// a `[String: Any]` never is.
///
/// Decoding an older payload just leaves newly added optionals nil, which is
/// the empty state both sides already render. Nothing here needs a version
/// number.
public enum TareWatchPayload {

    /// Phone → watch, via `updateApplicationContext`. Latest-wins and
    /// coalescing, which is right for a snapshot: an undelivered one is
    /// worthless the moment a newer one exists.
    public static let snapshotKey = "tare.watch.snapshot"

    /// Watch → phone, via `transferUserInfo`. Queued and guaranteed, which is
    /// right for a log entry: dropping one loses a reading the user believes
    /// they recorded.
    public static let entryKey = "tare.watch.entry"

    public static func encode(_ snapshot: TareWidgetSnapshot) -> [String: Data] {
        guard let data = try? JSONEncoder().encode(snapshot) else { return [:] }
        return [snapshotKey: data]
    }

    public static func encode(_ entry: TareWatchLogEntry) -> [String: Data] {
        guard let data = try? JSONEncoder().encode(entry) else { return [:] }
        return [entryKey: data]
    }

    public static func decodeSnapshot(_ data: Data?) -> TareWidgetSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(TareWidgetSnapshot.self, from: data)
    }

    public static func decodeEntry(_ data: Data?) -> TareWatchLogEntry? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(TareWatchLogEntry.self, from: data)
    }
}
