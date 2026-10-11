import Foundation

/// Durable tasks with optional imported planning context.
struct WeeklyPlan: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var id: String
    var sourceID: String?
    var timeZoneIdentifier: String?
    var horizon: PlanHorizon?
    var availability: [DailyAvailability]?
    var tasks: [PlannedTask]
    var allocations: [PlannedAllocation]
    var fixedCommitments: [FixedCommitment]
    var localState: PlanLocalState = PlanLocalState()

    var originalEffortSeconds: TimeInterval {
        tasks.reduce(0) { total, task in
            guard let estimate = task.originalEstimateSeconds,
                  task.parentEstimateAccounting != .usesParentEstimate else { return total }
            return total + estimate
        }
    }

    var remainingEffortSeconds: TimeInterval {
        tasks.reduce(0) { total, task in
            guard task.completedAt == nil, let estimate = task.remainingEstimateSeconds else { return total }
            return total + estimate
        }
    }

    var hasUnknownRemainingEffort: Bool {
        tasks.contains { $0.completedAt == nil && $0.remainingEstimateSeconds == nil }
    }

    func actualWorkSeconds(for taskID: String) -> TimeInterval {
        localState.workSegments.filter { $0.taskID == taskID }.reduce(0) { $0 + $1.duration }
    }

    func actualWorkSecondsIncludingDescendants(for taskID: String) -> TimeInterval {
        let included = descendantIDs(of: taskID).union([taskID])
        return localState.workSegments
            .filter { $0.taskID.map(included.contains) ?? false }
            .reduce(0) { $0 + $1.duration }
    }

    func descendantIDs(of taskID: String) -> Set<String> {
        var result = Set<String>()
        var pending = [taskID]
        while let parentID = pending.popLast() {
            for child in tasks where child.parentTaskID == parentID && result.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return result
    }

    /// Creates a child and applies its parent estimate choice together.
    mutating func addChild(
        _ child: PlannedTask,
        to parentID: String,
        accounting: ChildEstimateAccounting,
        recordedAt: Date = Date()
    ) throws {
        guard !tasks.contains(where: { $0.id == child.id }) else {
            throw PlanValidationError(path: "tasks.id", message: "Duplicate identity '\(child.id)'.")
        }
        guard let parentIndex = tasks.firstIndex(where: { $0.id == parentID }) else {
            throw PlanValidationError(path: "tasks.parentTaskID", message: "Unknown parent task '\(parentID)'.")
        }
        guard child.parentTaskID == nil, child.parentEstimateAccounting == nil else {
            throw PlanValidationError(path: "tasks.parentTaskID", message: "A new child already has parent information.")
        }

        var copy = self
        var child = child
        child.parentTaskID = parentID
        child.parentEstimateAccounting = accounting
        let amount = child.remainingEstimateSeconds
        if accounting == .usesParentEstimate, let amount,
           let parentRemaining = copy.tasks[parentIndex].remainingEstimateSeconds {
            guard amount <= parentRemaining else {
                throw PlanValidationError(path: "tasks.parentEstimateAccounting", message: "Child effort exceeds the parent's known remaining estimate.")
            }
            copy.tasks[parentIndex].remainingEstimateSeconds = parentRemaining - amount
        }
        copy.tasks.append(child)
        copy.localState.estimateAdjustments.append(TaskEstimateAdjustment(
            parentTaskID: parentID,
            childTaskID: child.id,
            accounting: accounting,
            amountSeconds: amount,
            recordedAt: recordedAt
        ))
        try copy.validate()
        self = copy
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
        sourceID = try values.decodeIfPresent(String.self, forKey: .sourceID)
        timeZoneIdentifier = try values.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        horizon = try values.decodeIfPresent(PlanHorizon.self, forKey: .horizon)
        availability = try values.decodeIfPresent([DailyAvailability].self, forKey: .availability)
        tasks = try values.decode([PlannedTask].self, forKey: .tasks)
        allocations = try values.decodeIfPresent([PlannedAllocation].self, forKey: .allocations) ?? []
        fixedCommitments = try values.decodeIfPresent([FixedCommitment].self, forKey: .fixedCommitments) ?? []
        localState = try values.decodeIfPresent(PlanLocalState.self, forKey: .localState) ?? PlanLocalState()
        try validate()
    }
}

extension WeeklyPlan {
    init(
        id: String, sourceID: String? = nil, timeZoneIdentifier: String? = nil,
        horizon: PlanHorizon? = nil, availability: [DailyAvailability]? = nil,
        tasks: [PlannedTask], allocations: [PlannedAllocation] = [],
        fixedCommitments: [FixedCommitment] = [], localState: PlanLocalState = PlanLocalState()
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

enum ChildEstimateAccounting: String, Codable, Equatable {
    case usesParentEstimate
    case addsToParentEstimate
}

struct PlannedTask: Codable, Equatable, Identifiable {
    var id: String
    var sourceID: String?
    var title: String
    var originalEstimateSeconds: TimeInterval?
    var remainingEstimateSeconds: TimeInterval?
    var completedAt: Date?
    var order: Int?
    var deadline: Date?
    var prerequisiteTaskIDs: [String]
    var parentTaskID: String?
    var parentEstimateAccounting: ChildEstimateAccounting?
    var project: String?
    var context: String?
    var minimumChunkSeconds: TimeInterval?
    var categoryTags: [String]

    var needsEstimateRevision: Bool { completedAt == nil && remainingEstimateSeconds == 0 }
    var hasUnknownEstimate: Bool { originalEstimateSeconds == nil && remainingEstimateSeconds == nil }
}

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
    var taskOrder: [String]? = nil
    var deferrals: [TaskDeferral] = []
    var estimateAdjustments: [TaskEstimateAdjustment] = []
    var workSegments: [TaskWorkSegment] = []
}

struct TaskEstimateAdjustment: Codable, Equatable, Identifiable {
    var id: UUID
    var parentTaskID: String
    var childTaskID: String
    var accounting: ChildEstimateAccounting
    var amountSeconds: TimeInterval?
    var recordedAt: Date

    init(id: UUID = UUID(), parentTaskID: String, childTaskID: String,
         accounting: ChildEstimateAccounting, amountSeconds: TimeInterval?, recordedAt: Date) {
        self.id = id
        self.parentTaskID = parentTaskID
        self.childTaskID = childTaskID
        self.accounting = accounting
        self.amountSeconds = amountSeconds
        self.recordedAt = recordedAt
    }
}

struct TaskDeferral: Codable, Equatable {
    var taskID: String
    var deferredAt: Date
    var until: Date
}

struct TaskWorkSegment: Codable, Equatable, Identifiable {
    var id: UUID
    var taskID: String?
    var runID: UUID
    var focusIntervalID: UUID
    var time: PlanTimeRange
    var duration: TimeInterval { time.duration }

    init(id: UUID = UUID(), taskID: String?, runID: UUID, focusInterval: ScheduledInterval, start: Date, end: Date) throws {
        guard focusInterval.kind == .focus else {
            throw PlanValidationError(path: "workSegment.focusIntervalID", message: "Actual work must belong to a focus interval, not a break.")
        }
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              start < end, start >= focusInterval.startDate, end <= focusInterval.endDate,
              end.timeIntervalSince(start) <= focusInterval.duration else {
            throw PlanValidationError(path: "workSegment.time", message: "Work must fit inside the credited focus interval.")
        }
        self.id = id; self.taskID = taskID; self.runID = runID; focusIntervalID = focusInterval.id
        time = PlanTimeRange(start: start, end: end)
    }
}

struct PlanValidationError: Error, Equatable, LocalizedError {
    let path: String
    let message: String
    var errorDescription: String? { "\(path): \(message)" }
}

enum WeeklyPlanJSON {
    static func decode(_ data: Data) throws -> WeeklyPlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = timestampFormatter(fractional: true).date(from: value) ?? timestampFormatter(fractional: false).date(from: value),
                  value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,3})?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$"#, options: .regularExpression) != nil,
                  WeeklyPlan.isValidDay(String(value.prefix(10))) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected an ISO 8601 timestamp with seconds and an explicit offset."))
            }
            return date
        }
        do { return try decoder.decode(WeeklyPlan.self, from: data) }
        catch let error as DecodingError {
            let context: DecodingError.Context
            let message: String
            switch error {
            case let .keyNotFound(key, details): throw PlanValidationError(path: path(details.codingPath + [key]), message: "Required field is missing.")
            case let .typeMismatch(_, details): context = details; message = "Incorrect value type. \(details.debugDescription)"
            case let .valueNotFound(_, details): context = details; message = "Required value is null."
            case let .dataCorrupted(details): context = details; message = details.debugDescription
            @unknown default: throw error
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

private extension String { var nonEmptyPath: String { isEmpty ? "$" : self } }
