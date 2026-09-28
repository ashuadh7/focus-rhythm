import Foundation

/// A snapshot of source planning and local execution. Import merging and storage are
/// separate operations; decoding a snapshot never starts or changes the timer.
struct WeeklyPlan: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var id: String
    var sourceID: String
    var timeZoneIdentifier: String
    var horizon: PlanHorizon
    /// Missing days are unknown; a listed day with no windows is explicitly unavailable.
    var availability: [DailyAvailability]?
    var tasks: [PlannedTask]
    var allocations: [PlannedAllocation]
    var fixedCommitments: [FixedCommitment]
    var localState: PlanLocalState = PlanLocalState()

    var originalEffortSeconds: TimeInterval {
        tasks.reduce(0) { $0 + $1.originalEstimateSeconds }
    }

    var remainingEffortSeconds: TimeInterval {
        tasks.filter { $0.completedAt == nil }.reduce(0) { $0 + $1.remainingEstimateSeconds }
    }

    func actualWorkSeconds(for taskID: String) -> TimeInterval {
        localState.workSegments.filter { $0.taskID == taskID }.reduce(0) { $0 + $1.duration }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, sourceID, timeZoneIdentifier, horizon, availability
        case tasks, allocations, fixedCommitments, localState
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PlanValidationError(path: "schemaVersion", message: "Unsupported version \(schemaVersion); expected 1.")
        }
        id = try values.decode(String.self, forKey: .id)
        sourceID = try values.decode(String.self, forKey: .sourceID)
        timeZoneIdentifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
        horizon = try values.decode(PlanHorizon.self, forKey: .horizon)
        availability = try values.decodeIfPresent([DailyAvailability].self, forKey: .availability)
        tasks = try values.decode([PlannedTask].self, forKey: .tasks)
        allocations = try values.decode([PlannedAllocation].self, forKey: .allocations)
        fixedCommitments = try values.decode([FixedCommitment].self, forKey: .fixedCommitments)
        localState = try values.decodeIfPresent(PlanLocalState.self, forKey: .localState) ?? PlanLocalState()
        try validate()
    }
}

// Keep memberwise construction available alongside the validating Codable initializer.
extension WeeklyPlan {
    init(
        id: String, sourceID: String, timeZoneIdentifier: String, horizon: PlanHorizon,
        availability: [DailyAvailability]? = nil, tasks: [PlannedTask],
        allocations: [PlannedAllocation] = [], fixedCommitments: [FixedCommitment] = [],
        localState: PlanLocalState = PlanLocalState()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.horizon = horizon
        self.availability = availability
        self.tasks = tasks
        self.allocations = allocations
        self.fixedCommitments = fixedCommitments
        self.localState = localState
    }
}

/// ISO Gregorian calendar dates, interpreted in the plan's explicit timezone.
struct PlanHorizon: Codable, Equatable {
    var startDay: String
    var endDayExclusive: String
}

struct PlanTimeRange: Codable, Equatable {
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct DailyAvailability: Codable, Equatable {
    var day: String
    var windows: [PlanTimeRange]
}

struct PlannedTask: Codable, Equatable, Identifiable {
    var id: String
    /// Stable external item identity, absent for locally created tasks.
    var sourceID: String?
    var title: String
    var originalEstimateSeconds: TimeInterval
    /// Stored independently: zero does not imply completion or change the rhythm.
    var remainingEstimateSeconds: TimeInterval
    var completedAt: Date?
    var order: Int
    var deadline: Date?
    var prerequisiteTaskIDs: [String]
    var project: String?
    var context: String?
    var minimumChunkSeconds: TimeInterval?
    var categoryTags: [String]

    var needsEstimateRevision: Bool {
        completedAt == nil && remainingEstimateSeconds == 0
    }
}

/// A flexible suggestion referencing one task, never another copy of its effort.
struct PlannedAllocation: Codable, Equatable, Identifiable {
    var id: String
    var taskID: String
    var preferredDay: String
    var suggestedTime: PlanTimeRange?
    var plannedEffortSeconds: TimeInterval?
}

struct FixedCommitment: Codable, Equatable, Identifiable {
    var id: String
    var sourceID: String?
    var title: String
    var time: PlanTimeRange
}

struct PlanLocalState: Codable, Equatable {
    /// When present, a complete permutation of task IDs; otherwise use task.order.
    var taskOrder: [String]? = nil
    var deferrals: [TaskDeferral] = []
    var workSegments: [TaskWorkSegment] = []
}

struct TaskDeferral: Codable, Equatable {
    var taskID: String
    var deferredAt: Date
    var until: Date
}

/// Closed, non-overlapping actual focus spans. Nil taskID means unattributed focus.
/// Segment and interval identities survive task switches and replay after relaunch.
struct TaskWorkSegment: Codable, Equatable, Identifiable {
    var id: UUID
    var taskID: String?
    var runID: UUID
    var focusIntervalID: UUID
    var time: PlanTimeRange

    var duration: TimeInterval { time.duration }

    init(
        id: UUID = UUID(), taskID: String?, runID: UUID,
        focusInterval: ScheduledInterval, start: Date, end: Date
    ) throws {
        guard focusInterval.kind == .focus else {
            throw PlanValidationError(path: "workSegment.focusIntervalID", message: "Actual work must belong to a focus interval, not a break.")
        }
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite,
              start < end, start >= focusInterval.startDate, end <= focusInterval.endDate,
              end.timeIntervalSince(start) <= focusInterval.duration else {
            throw PlanValidationError(path: "workSegment.time", message: "Work must fit inside the credited focus interval.")
        }
        self.id = id
        self.taskID = taskID
        self.runID = runID
        focusIntervalID = focusInterval.id
        time = PlanTimeRange(start: start, end: end)
    }
}

struct PlanValidationError: Error, Equatable, LocalizedError {
    let path: String
    let message: String
    var errorDescription: String? { "\(path): \(message)" }
}

/// The external contract uses ISO 8601 timestamps, unlike default Codable Date numbers.
/// Native Codable remains usable for local persistence with its own date strategy.
enum WeeklyPlanJSON {
    static func decode(_ data: Data) throws -> WeeklyPlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = timestampFormatter(fractional: true).date(from: value)
                ?? timestampFormatter(fractional: false).date(from: value),
                value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,3})?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$"#, options: .regularExpression) != nil,
                WeeklyPlan.isValidDay(String(value.prefix(10))) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Expected an ISO 8601 timestamp with seconds and an explicit offset (at most millisecond precision)."))
            }
            return date
        }
        do {
            return try decoder.decode(WeeklyPlan.self, from: data)
        } catch let error as DecodingError {
            let context: DecodingError.Context
            let message: String
            switch error {
            case let .keyNotFound(key, details):
                throw PlanValidationError(path: path(details.codingPath + [key]), message: "Required field is missing.")
            case let .typeMismatch(_, details):
                context = details; message = "Incorrect value type. \(details.debugDescription)"
            case let .valueNotFound(_, details):
                context = details; message = "Required value is null."
            case let .dataCorrupted(details):
                context = details; message = details.debugDescription
            @unknown default:
                throw error
            }
            throw PlanValidationError(path: path(context.codingPath), message: message)
        }
    }

    static func encode(_ plan: WeeklyPlan) throws -> Data {
        try plan.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(timestampFormatter(fractional: true).string(from: date))
        }
        return try encoder.encode(plan)
    }

    private static func timestampFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.reduce("") { result, key in
            if let index = key.intValue { return "\(result)[\(index)]" }
            return result.isEmpty ? key.stringValue : "\(result).\(key.stringValue)"
        }.nonEmptyPath
    }
}

private extension String {
    var nonEmptyPath: String { isEmpty ? "$" : self }
}
