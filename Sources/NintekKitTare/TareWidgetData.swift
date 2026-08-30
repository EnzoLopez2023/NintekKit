import Foundation

/// The small snapshot Tare publishes for its home-screen, Lock Screen and
/// StandBy widgets. Written by the app after any screen changes the store, read
/// by the widget extension — handed across the process boundary through the
/// App Group.
///
/// Tare pins its SwiftData store to the *app* container on purpose (a store in
/// the group container fails to open on a simulator that has never had the
/// group provisioned), so the extension cannot read the database at all. This
/// snapshot is the entire contract between them.
///
/// Unlike the Workshop and ShopKeep snapshots there is no `signedIn` flag:
/// Tare has no account and no server, so the only two states are "has data"
/// and "doesn't", which every field already expresses by being optional.
///
/// Values are stored **already converted to the user's display units** and
/// paired with their unit label — the extension has no access to `Units` and
/// must never guess whether a number is mg/dL or mmol/L.
public struct TareWidgetSnapshot: Codable, Sendable, Equatable {

    /// Mirrors the app's `GlucoseStatusLabel`. Duplicated here rather than
    /// shared because the app's copy carries the threshold logic, which needs
    /// the reading type and belongs on the app side of the boundary.
    public enum GlucoseBand: String, Codable, Sendable, CaseIterable {
        case low = "Low"
        case normal = "Normal"
        case elevated = "Elevated"
        case high = "High"
    }

    // MARK: Dose

    /// When the last dose was taken. The **instant**, not a rendered countdown:
    /// the next dose is seven days later, so the extension can recompute
    /// "3 days" or "Today" at every local midnight from this one value without
    /// the app ever running. A pre-rendered string would go stale overnight.
    public var lastInjectionAt: Date?
    /// Milligrams of that dose, unformatted.
    public var doseMg: Double?
    public var medicationName: String?

    // MARK: Glucose

    /// Latest reading, in display units.
    public var glucoseValue: Double?
    /// `mg/dL` or `mmol/L`.
    public var glucoseUnit: String
    /// 0 for mg/dL, 1 for mmol/L.
    public var glucoseDecimals: Int
    public var glucoseBand: GlucoseBand?
    /// 30-day average, in display units.
    public var glucoseAverage30d: Double?
    /// Estimated A1C from the last 90 days of glucose readings.
    public var estimatedA1C90d: Double?
    /// Up to 30 points, oldest first, in display units.
    public var glucoseSpark: [Double]

    // MARK: Weight

    /// Latest weight, in display units.
    public var weightValue: Double?
    /// `lbs` or `kg`.
    public var weightUnit: String
    /// The goal, in display units. `nil` when unset — the widget then shows the
    /// trend instead of a progress arc.
    public var goalWeight: Double?
    /// The earliest logged weight, in display units. Together with the goal it
    /// gives the widget a denominator for "how far along am I".
    public var startWeight: Double?
    /// Signed 30-day change, in display units.
    public var weightDelta30d: Double?
    /// Up to 30 points, oldest first, in display units.
    public var weightSpark: [Double]

    // MARK: Steps

    /// Today's step total, as HealthKit reported it when the app last ran.
    ///
    /// Unlike the dose countdown this **cannot** be recomputed on the other
    /// side of the boundary: neither widget extension reads HealthKit, so the
    /// figure is only as fresh as the last publish. `stepsUpdatedAt` is carried
    /// with it so a surface that has room can say how old it is rather than
    /// presenting a stale count as current.
    public var stepsToday: Double?
    /// Mean over *completed* days in the published week — today excluded,
    /// because a day that is still accumulating drags the average down and the
    /// comparison it invites is not one anybody is making at breakfast.
    public var stepsAverage7d: Double?
    /// One total per day, oldest first, today last. Seven entries when the app
    /// has published, empty otherwise.
    public var stepsSpark: [Double]
    /// When the step figures above were read. `nil` when Health sync has never
    /// been on, which is also the state that leaves the others nil.
    public var stepsUpdatedAt: Date?

    public var updatedAt: Date

    public init(lastInjectionAt: Date? = nil, doseMg: Double? = nil,
                medicationName: String? = nil,
                glucoseValue: Double? = nil, glucoseUnit: String = "mg/dL",
                glucoseDecimals: Int = 0, glucoseBand: GlucoseBand? = nil,
                glucoseAverage30d: Double? = nil, estimatedA1C90d: Double? = nil,
                glucoseSpark: [Double] = [],
                weightValue: Double? = nil, weightUnit: String = "lbs",
                goalWeight: Double? = nil, startWeight: Double? = nil,
                weightDelta30d: Double? = nil, weightSpark: [Double] = [],
                stepsToday: Double? = nil, stepsAverage7d: Double? = nil,
                stepsSpark: [Double] = [], stepsUpdatedAt: Date? = nil,
                updatedAt: Date = Date()) {
        self.lastInjectionAt = lastInjectionAt
        self.doseMg = doseMg
        self.medicationName = medicationName
        self.glucoseValue = glucoseValue
        self.glucoseUnit = glucoseUnit
        self.glucoseDecimals = glucoseDecimals
        self.glucoseBand = glucoseBand
        self.glucoseAverage30d = glucoseAverage30d
        self.estimatedA1C90d = estimatedA1C90d
        self.glucoseSpark = glucoseSpark
        self.weightValue = weightValue
        self.weightUnit = weightUnit
        self.goalWeight = goalWeight
        self.startWeight = startWeight
        self.weightDelta30d = weightDelta30d
        self.weightSpark = weightSpark
        self.stepsToday = stepsToday
        self.stepsAverage7d = stepsAverage7d
        self.stepsSpark = stepsSpark
        self.stepsUpdatedAt = stepsUpdatedAt
        self.updatedAt = updatedAt
    }

    /// Every field empty — what a widget shows before the app has ever
    /// published, and what `clear()` writes.
    public static let empty = TareWidgetSnapshot()

    /// Decodes tolerantly, so a payload written by an older build still loads.
    ///
    /// The synthesised decoder would do the right thing for the optionals and
    /// the wrong thing for everything else: a missing key for a non-optional
    /// `[Double]` or `String` throws, and one thrown error fails the *whole*
    /// snapshot rather than the one field. That is how adding a spark array
    /// blanks every widget and complication on the device until the app is next
    /// opened — and on the watch, until the phone app is next opened, which
    /// could be days.
    ///
    /// So every field is read with `decodeIfPresent` against the same default
    /// the initialiser uses. Adding a field stays a one-line change with no
    /// version bump, which is the property the App Group hand-off is supposed
    /// to have.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        lastInjectionAt = try c.decodeIfPresent(Date.self, forKey: .lastInjectionAt)
        doseMg = try c.decodeIfPresent(Double.self, forKey: .doseMg)
        medicationName = try c.decodeIfPresent(String.self, forKey: .medicationName)
        glucoseValue = try c.decodeIfPresent(Double.self, forKey: .glucoseValue)
        glucoseUnit = try value(.glucoseUnit, "mg/dL")
        glucoseDecimals = try value(.glucoseDecimals, 0)
        glucoseBand = try c.decodeIfPresent(GlucoseBand.self, forKey: .glucoseBand)
        glucoseAverage30d = try c.decodeIfPresent(Double.self, forKey: .glucoseAverage30d)
        estimatedA1C90d = try c.decodeIfPresent(Double.self, forKey: .estimatedA1C90d)
        glucoseSpark = try value(.glucoseSpark, [])
        weightValue = try c.decodeIfPresent(Double.self, forKey: .weightValue)
        weightUnit = try value(.weightUnit, "lbs")
        goalWeight = try c.decodeIfPresent(Double.self, forKey: .goalWeight)
        startWeight = try c.decodeIfPresent(Double.self, forKey: .startWeight)
        weightDelta30d = try c.decodeIfPresent(Double.self, forKey: .weightDelta30d)
        weightSpark = try value(.weightSpark, [])
        stepsToday = try c.decodeIfPresent(Double.self, forKey: .stepsToday)
        stepsAverage7d = try c.decodeIfPresent(Double.self, forKey: .stepsAverage7d)
        stepsSpark = try value(.stepsSpark, [])
        stepsUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .stepsUpdatedAt)
        updatedAt = try value(.updatedAt, Date(timeIntervalSince1970: 0))
    }

    /// Fraction of the journey from `startWeight` to `goalWeight` completed,
    /// clamped to 0...1. `nil` unless all three weights are present and the
    /// start and goal actually differ.
    public var goalProgress: Double? {
        guard let start = startWeight, let goal = goalWeight, let now = weightValue,
              start != goal else { return nil }
        return min(1, max(0, (start - now) / (start - goal)))
    }

    /// A representative sample for the widget gallery and previews. The gallery
    /// renders before any App Group read, so this is what a person sees when
    /// deciding whether to add the widget — it has to look like a real week.
    public static let sample = TareWidgetSnapshot(
        lastInjectionAt: Calendar.current.date(byAdding: .day, value: -4, to: Date()),
        doseMg: 7.5,
        medicationName: "Ozempic",
        glucoseValue: 94, glucoseUnit: "mg/dL", glucoseDecimals: 0, glucoseBand: .normal,
        glucoseAverage30d: 101, estimatedA1C90d: 5.7,
        glucoseSpark: [112, 108, 103, 99, 101, 96, 94, 97, 93, 95, 92, 94, 97, 100, 96, 92],
        weightValue: 214.2, weightUnit: "lbs",
        goalWeight: 195, startWeight: 238, weightDelta30d: -4.6,
        weightSpark: [238, 234, 231, 228, 226, 223, 221, 219, 218, 216, 215, 214.2, 213.9, 213.4],
        stepsToday: 6482, stepsAverage7d: 8140,
        stepsSpark: [7420, 9130, 6890, 10240, 8010, 7150, 6482],
        stepsUpdatedAt: Date())

    /// Carries the step slice of `previous` onto this snapshot.
    ///
    /// Steps arrive on their own asynchronous path — HealthKit cannot be read
    /// synchronously, and the publish that follows a logged weight has no
    /// figures for them. Without this, every ordinary publish would blank the
    /// steps complication until the next HealthKit read landed, so a face
    /// would flicker to "—" each time the user recorded anything at all.
    public mutating func carryStepsForward(from previous: TareWidgetSnapshot?) {
        guard let previous else { return }
        stepsToday = previous.stepsToday
        stepsAverage7d = previous.stepsAverage7d
        stepsSpark = previous.stepsSpark
        stepsUpdatedAt = previous.stepsUpdatedAt
    }
}

/// Reads and writes ``TareWidgetSnapshot`` in the App Group's shared
/// `UserDefaults` suite — the hand-off point between the Tare app and its
/// widget extension. The group (`group.com.nintek.tare`) must be enabled on
/// both targets.
public enum TareWidgetStore {
    public static let appGroup = "group.com.nintek.tare"
    private static let key = "tare.widget.snapshot"

    public static func save(_ snapshot: TareWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }

    public static func load() -> TareWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TareWidgetSnapshot.self, from: data)
    }

    /// Wipes the published health data. Called when the store is emptied — a
    /// restored backup or a "delete everything" — because a widget left
    /// showing the previous data would outlive the records it came from.
    public static func clear() { save(.empty) }

    /// Merges a partial update into the stored snapshot, preserving the slices
    /// it does not touch.
    ///
    /// Tare publishes the whole snapshot from one place today, so nothing needs
    /// this yet. It exists because the moment a second writer appears — a
    /// HealthKit background delivery landing a weight while the dose slice is
    /// untouched — a plain `save` from either side silently clobbers the
    /// other's fields, which is exactly the bug Workshop had to fix.
    public static func update(_ mutate: (inout TareWidgetSnapshot) -> Void) {
        var snapshot = load() ?? .empty
        mutate(&snapshot)
        snapshot.updatedAt = Date()
        save(snapshot)
    }
}
