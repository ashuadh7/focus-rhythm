import Foundation

struct RhythmVariation: Codable, Equatable, Identifiable {
    let id: UUID
    var rhythm: DailyRhythm

    init(id: UUID = UUID(), rhythm: DailyRhythm) {
        self.id = id
        self.rhythm = rhythm
    }
}

struct PlannedRhythmSelection: Codable, Equatable {
    let dateKey: String
    let variationID: UUID
}

struct LongBreakWarningTiming: Codable, Equatable {
    let wrapUpLeadTime: TimeInterval
    let finalReturnLeadTime: TimeInterval
}

struct RunAdjustment: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case midWorkBreak
        case skippedBreak
        case extendedFocus
        case extendedLongBreak
    }

    let id: UUID
    let kind: Kind
    let date: Date
    let duration: TimeInterval
    let label: String

    init(id: UUID = UUID(), kind: Kind, date: Date, duration: TimeInterval, label: String) {
        self.id = id
        self.kind = kind
        self.date = date
        self.duration = duration
        self.label = label
    }
}

struct ActiveRhythmRun: Codable, Equatable {
    let id: UUID
    enum Status: String, Codable {
        case active
        case completed
        case ended
    }

    let variationID: UUID?
    let rhythm: DailyRhythm
    var schedule: GeneratedDailySchedule
    let startedAt: Date
    var scheduleRevision: Int
    var recordedIntervalIDs: Set<UUID>
    var extendedIntervalIDs: Set<UUID>
    var status: Status
    var quickBreakEndsAt: Date?
    var longBreakWarningTiming: LongBreakWarningTiming?
    var adjustments: [RunAdjustment]

    init(
        id: UUID = UUID(),
        variationID: UUID?,
        rhythm: DailyRhythm,
        schedule: GeneratedDailySchedule,
        startedAt: Date,
        scheduleRevision: Int = 1,
        recordedIntervalIDs: Set<UUID> = [],
        extendedIntervalIDs: Set<UUID> = [],
        status: Status = .active,
        quickBreakEndsAt: Date? = nil,
        longBreakWarningTiming: LongBreakWarningTiming? = nil,
        adjustments: [RunAdjustment] = []
    ) {
        self.id = id
        self.variationID = variationID
        self.rhythm = rhythm
        self.schedule = schedule
        self.startedAt = startedAt
        self.scheduleRevision = scheduleRevision
        self.recordedIntervalIDs = recordedIntervalIDs
        self.extendedIntervalIDs = extendedIntervalIDs
        self.status = status
        self.quickBreakEndsAt = quickBreakEndsAt
        self.longBreakWarningTiming = longBreakWarningTiming
        self.adjustments = adjustments
    }

    private enum CodingKeys: String, CodingKey {
        case id, variationID, rhythm, schedule, startedAt, scheduleRevision, recordedIntervalIDs, extendedIntervalIDs, status
        case quickBreakEndsAt, longBreakWarningTiming, adjustments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        variationID = try container.decodeIfPresent(UUID.self, forKey: .variationID)
        rhythm = try container.decode(DailyRhythm.self, forKey: .rhythm)
        schedule = try container.decode(GeneratedDailySchedule.self, forKey: .schedule)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        scheduleRevision = try container.decodeIfPresent(Int.self, forKey: .scheduleRevision) ?? 1
        recordedIntervalIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .recordedIntervalIDs) ?? []
        extendedIntervalIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .extendedIntervalIDs) ?? []
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .active
        quickBreakEndsAt = try container.decodeIfPresent(Date.self, forKey: .quickBreakEndsAt)
        longBreakWarningTiming = try container.decodeIfPresent(LongBreakWarningTiming.self, forKey: .longBreakWarningTiming)
        adjustments = try container.decodeIfPresent([RunAdjustment].self, forKey: .adjustments) ?? []
    }
}

enum RunEndMode: String, CaseIterable, Identifiable {
    case stopAt
    case focusFor

    var id: Self { self }
}

enum RunEndCondition: Equatable {
    case stopAt(TimeOfDay)
    case focusFor(TimeInterval)
}

struct RhythmLibrary: Codable, Equatable {
    var variations: [RhythmVariation]
    var defaultVariationID: UUID?
    var plannedSelections: [PlannedRhythmSelection]
    var activeRun: ActiveRhythmRun?

    static let empty = RhythmLibrary(
        variations: [],
        defaultVariationID: nil,
        plannedSelections: [],
        activeRun: nil
    )
}
