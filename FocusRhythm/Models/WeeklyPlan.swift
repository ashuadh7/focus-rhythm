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

    /// The durable queue is deliberately independent from the timer. Selecting or
    /// deferring a task changes what is offered next, never the running interval.
    func taskQueue(
        at date: Date,
        availableFocusSeconds: TimeInterval? = nil,
        deadlineAtRiskTaskIDs: Set<String> = []
    ) -> TaskQueue {
        let completed = Set(tasks.compactMap { $0.completedAt == nil ? nil : $0.id })
        let ordered = orderedTasks.filter { task in
            guard task.completedAt == nil, task.abandonedAt == nil,
                  !task.needsEstimateRevision,
                  task.prerequisiteTaskIDs.allSatisfy(completed.contains)
            else { return false }
            guard let availableFocusSeconds, let minimum = task.minimumChunkSeconds else { return true }
            return availableFocusSeconds >= minimum
        }

        let deferrals = Dictionary(uniqueKeysWithValues: localState.deferrals.map { ($0.taskID, $0) })
        let returnedForDeadline = ordered.filter {
            guard let deferral = deferrals[$0.id] else { return false }
            return deferral.until > date && deadlineAtRiskTaskIDs.contains($0.id)
        }.map(\.id)
        let deferred = ordered.filter {
            guard let deferral = deferrals[$0.id] else { return false }
            return deferral.until > date && !deadlineAtRiskTaskIDs.contains($0.id)
        }
        let ready = ordered.filter { task in
            !deferred.contains(where: { $0.id == task.id })
        }
        return TaskQueue(
            readyTasks: ready,
            deferredTasks: deferred,
            selectedTaskID: localState.selectedTaskID,
            nextDeferredReturn: deferred.map { deferrals[$0.id]!.until }.min(),
            returnedForDeadline: returnedForDeadline
        )
    }

    mutating func reorderTasks(_ orderedIDs: [String]) throws {
        guard Set(orderedIDs) == Set(tasks.map(\.id)), orderedIDs.count == tasks.count else {
            throw PlanValidationError(path: "localState.taskOrder", message: "Order must contain every task exactly once.")
        }
        var copy = self
        copy.localState.taskOrder = orderedIDs
        try copy.validate()
        self = copy
    }

    mutating func deferTask(_ taskID: String, at date: Date, for duration: TimeInterval = 30 * 60) throws {
        guard duration.isFinite, duration > 0 else {
            throw PlanValidationError(path: "localState.deferrals", message: "Deferral duration must be positive.")
        }
        guard let task = tasks.first(where: { $0.id == taskID }), task.completedAt == nil, task.abandonedAt == nil else {
            throw PlanValidationError(path: "localState.deferrals", message: "Only unfinished tasks can be postponed.")
        }
        let completed = Set(tasks.compactMap { $0.completedAt == nil ? nil : $0.id })
        guard task.prerequisiteTaskIDs.allSatisfy(completed.contains) else {
            throw PlanValidationError(path: "localState.deferrals", message: "Finish prerequisites before postponing this task.")
        }
        var copy = self
        copy.localState.deferrals.removeAll { $0.taskID == taskID }
        copy.localState.deferrals.append(TaskDeferral(taskID: taskID, deferredAt: date, until: date.addingTimeInterval(duration)))
        if copy.localState.selectedTaskID == taskID { copy.localState.selectedTaskID = nil }
        try copy.validate()
        self = copy
    }

    mutating func selectTask(_ taskID: String) throws {
        guard let task = tasks.first(where: { $0.id == taskID }), task.completedAt == nil, task.abandonedAt == nil, !task.needsEstimateRevision else {
            throw PlanValidationError(path: "localState.selectedTaskID", message: "Only unfinished tasks with usable effort can be selected.")
        }
        let completed = Set(tasks.compactMap { $0.completedAt == nil ? nil : $0.id })
        guard task.prerequisiteTaskIDs.allSatisfy(completed.contains) else {
            throw PlanValidationError(path: "localState.selectedTaskID", message: "Finish prerequisites before selecting this task.")
        }
        var copy = self
        copy.localState.selectedTaskID = taskID
        copy.localState.deferrals.removeAll { $0.taskID == taskID }
        try copy.validate()
        self = copy
    }

    /// Completion is an explicit decision. Reaching a zero remaining estimate never
    /// calls this automatically: estimates describe expectation, while work segments
    /// describe what actually happened.
    mutating func markTaskCompleted(
        _ taskID: String,
        at date: Date,
        descendantDisposition: ActiveDescendantDisposition? = nil
    ) throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }), tasks[index].completedAt == nil, tasks[index].abandonedAt == nil else {
            throw PlanValidationError(path: "tasks.completedAt", message: "Only unfinished tasks can be marked done.")
        }
        let activeDescendants = activeDescendantIndices(of: taskID)
        if !activeDescendants.isEmpty && descendantDisposition == nil {
            throw PlanValidationError(path: "tasks.completedAt", message: "Review unfinished child tasks before completing this parent.")
        }
        var copy = self
        copy.tasks[index].completedAt = date
        copy.localState.deferrals.removeAll { $0.taskID == taskID }
        if copy.localState.selectedTaskID == taskID { copy.localState.selectedTaskID = nil }
        if let descendantDisposition {
            copy.apply(descendantDisposition, to: activeDescendants, at: date)
        }
        try copy.validate()
        self = copy
    }

    /// Adds an app-owned task to the same catalog used for imported work.  The
    /// operation also powers child creation so hierarchy never needs a second task
    /// type or persistence path.
    @discardableResult
    mutating func addLocalTask(
        title: String,
        estimateSeconds: TimeInterval?,
        deadline: Date? = nil,
        project: String? = nil,
        context: String? = nil,
        categoryTags: [String] = [],
        parentID: String? = nil,
        accounting: ChildEstimateAccounting? = nil,
        recordedAt: Date = Date()
    ) throws -> String {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            throw PlanValidationError(path: "tasks.title", message: "A task needs a title.")
        }
        guard estimateSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw PlanValidationError(path: "tasks.estimate", message: "Estimate must be finite and nonnegative.")
        }
        guard (parentID == nil) == (accounting == nil) else {
            throw PlanValidationError(path: "tasks.parentTaskID", message: "A child needs an estimate-accounting choice.")
        }
        let task = PlannedTask(
            id: UUID().uuidString, sourceID: nil, title: cleanedTitle,
            originalEstimateSeconds: estimateSeconds, remainingEstimateSeconds: estimateSeconds,
            completedAt: nil, abandonedAt: nil, order: nil, deadline: deadline,
            prerequisiteTaskIDs: [], parentTaskID: nil, parentEstimateAccounting: nil,
            project: project?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            context: context?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            minimumChunkSeconds: nil, categoryTags: categoryTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
        if let parentID, let accounting {
            try addChild(task, to: parentID, accounting: accounting, recordedAt: recordedAt)
        } else {
            let existingOrder = normalizedTaskOrder()
            var copy = self
            copy.tasks.append(task)
            copy.localState.taskOrder = existingOrder + [task.id]
            try copy.validate()
            self = copy
        }
        return task.id
    }

    mutating func editLocalTask(
        _ taskID: String, title: String, estimateSeconds: TimeInterval?, deadline: Date?,
        project: String?, context: String?, categoryTags: [String],
        parentID: String? = nil, accounting: ChildEstimateAccounting? = nil,
        recordedAt: Date = Date()
    ) throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID && $0.sourceID == nil }) else {
            throw PlanValidationError(path: "tasks.id", message: "Only local tasks can be edited here.")
        }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { throw PlanValidationError(path: "tasks.title", message: "A task needs a title.") }
        guard estimateSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw PlanValidationError(path: "tasks.estimate", message: "Estimate must be finite and nonnegative.")
        }
        guard (parentID == nil) == (accounting == nil) else {
            throw PlanValidationError(path: "tasks.parentTaskID", message: "A child needs an estimate-accounting choice.")
        }
        if let parentID {
            guard tasks.contains(where: { $0.id == parentID }), parentID != taskID,
                  !descendantIDs(of: taskID).contains(parentID) else {
                throw PlanValidationError(path: "tasks.parentTaskID", message: "A task cannot be placed inside itself or one of its children.")
            }
        }

        var copy = self
        // Undo the current allocation using the child's *current* remaining work,
        // then apply the edited relationship and estimate in the same candidate.
        // This keeps known remaining work constant unless the person explicitly
        // changes the estimate or selects "Add to estimate".
        let oldTask = copy.tasks[index]
        if oldTask.parentEstimateAccounting == .usesParentEstimate,
           let oldParentID = oldTask.parentTaskID,
           let oldParentIndex = copy.tasks.firstIndex(where: { $0.id == oldParentID }),
           let childRemaining = oldTask.remainingEstimateSeconds,
           let parentRemaining = copy.tasks[oldParentIndex].remainingEstimateSeconds {
            copy.tasks[oldParentIndex].remainingEstimateSeconds = parentRemaining + childRemaining
        }
        copy.tasks[index].title = cleanedTitle
        copy.tasks[index].originalEstimateSeconds = estimateSeconds
        copy.tasks[index].remainingEstimateSeconds = estimateSeconds
        copy.tasks[index].deadline = deadline
        copy.tasks[index].project = project?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        copy.tasks[index].context = context?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        copy.tasks[index].categoryTags = categoryTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        copy.tasks[index].parentTaskID = parentID
        copy.tasks[index].parentEstimateAccounting = accounting
        if let parentID, let accounting {
            guard let parentIndex = copy.tasks.firstIndex(where: { $0.id == parentID }) else { fatalError("Validated above") }
            if accounting == .usesParentEstimate,
               let amount = estimateSeconds,
               let parentRemaining = copy.tasks[parentIndex].remainingEstimateSeconds {
                guard amount <= parentRemaining else {
                    throw PlanValidationError(path: "tasks.parentEstimateAccounting", message: "Child effort exceeds the parent's known remaining estimate.")
                }
                copy.tasks[parentIndex].remainingEstimateSeconds = parentRemaining - amount
            }
            copy.localState.estimateAdjustments.append(TaskEstimateAdjustment(
                parentTaskID: parentID, childTaskID: taskID, accounting: accounting,
                amountSeconds: estimateSeconds, recordedAt: copy.nextAdjustmentDate(after: recordedAt, for: taskID)
            ))
        }
        try copy.validate()
        self = copy
    }

    /// Abandonment is explicit and durable. It preserves actual work and task
    /// history, unlike postponement, which keeps a task active in the queue.
    mutating func abandonLocalTask(
        _ taskID: String,
        at date: Date,
        descendantDisposition: ActiveDescendantDisposition? = nil
    ) throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID && $0.sourceID == nil && $0.completedAt == nil && $0.abandonedAt == nil }) else {
            throw PlanValidationError(path: "tasks.abandonedAt", message: "Only active local tasks can be abandoned.")
        }
        let activeDescendants = activeDescendantIndices(of: taskID)
        if !activeDescendants.isEmpty && descendantDisposition == nil {
            throw PlanValidationError(path: "tasks.abandonedAt", message: "Review unfinished child tasks before abandoning this parent.")
        }
        var copy = self
        copy.tasks[index].abandonedAt = date
        copy.localState.deferrals.removeAll { $0.taskID == taskID }
        if copy.localState.selectedTaskID == taskID { copy.localState.selectedTaskID = nil }
        if let descendantDisposition {
            copy.apply(descendantDisposition, to: activeDescendants, at: date)
        }
        try copy.validate()
        self = copy
    }

    private var orderedTasks: [PlannedTask] {
        let positions = Dictionary(uniqueKeysWithValues: (localState.taskOrder ?? []).enumerated().map { ($0.element, $0.offset) })
        return tasks.sorted { left, right in
            let leftPosition = positions[left.id] ?? (left.order ?? Int.max)
            let rightPosition = positions[right.id] ?? (right.order ?? Int.max)
            return leftPosition == rightPosition ? left.id < right.id : leftPosition < rightPosition
        }
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
        let orderBeforeChild = copy.normalizedTaskOrder()
        copy.tasks.append(child)
        copy.localState.taskOrder = orderBeforeChild + [child.id]
        copy.localState.estimateAdjustments.append(TaskEstimateAdjustment(
            parentTaskID: parentID,
            childTaskID: child.id,
            accounting: accounting,
            amountSeconds: amount,
            recordedAt: copy.nextAdjustmentDate(after: recordedAt, for: child.id)
        ))
        try copy.validate()
        self = copy
    }

    private func activeDescendantIndices(of taskID: String) -> [Int] {
        let ids = descendantIDs(of: taskID)
        return tasks.indices.filter { ids.contains(tasks[$0].id) && tasks[$0].completedAt == nil && tasks[$0].abandonedAt == nil }
    }

    private mutating func apply(_ disposition: ActiveDescendantDisposition, to indices: [Int], at date: Date) {
        for index in indices {
            switch disposition {
            case .completeDescendants: tasks[index].completedAt = date
            case .abandonDescendants: tasks[index].abandonedAt = date
            }
            localState.deferrals.removeAll { $0.taskID == tasks[index].id }
            if localState.selectedTaskID == tasks[index].id { localState.selectedTaskID = nil }
        }
    }

    private func nextAdjustmentDate(after proposed: Date, for childID: String) -> Date {
        guard let latest = localState.estimateAdjustments.last(where: { $0.childTaskID == childID })?.recordedAt,
              proposed <= latest else { return proposed }
        return latest.addingTimeInterval(0.001)
    }

    /// Imported snapshots and debug fixtures can predate a locally appended task.
    /// Keep an existing intentional order, but always append any unrepresented task
    /// before adding another one so persistence validation stays strict.
    private func normalizedTaskOrder() -> [String] {
        let preferred = localState.taskOrder ?? orderedTasks.map(\.id)
        let known = Set(preferred)
        return preferred + tasks.map(\.id).filter { !known.contains($0) }
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

/// A transparent, non-mutating answer to “what can fit?”  Forecasting consumes
/// only real focus capacity; it never turns a preference or estimate into an anchor.
struct TaskForecast: Equatable {
    struct Placement: Equatable, Identifiable {
        let id: String
        let taskID: String
        let day: String
        let effortSeconds: TimeInterval
    }

    enum Conflict: Equatable {
        case insufficientKnownCapacity(shortfallSeconds: TimeInterval)
        case deadlineAtRisk(taskID: String)
        case prerequisiteIncomplete(taskID: String)
        case missingFutureAvailability
    }

    var placements: [Placement]
    var unplacedTaskIDs: [String]
    var unknownEffortTaskIDs: [String]
    var conflicts: [Conflict]
    var knownCapacitySeconds: TimeInterval
    var knownDemandSeconds: TimeInterval

    var knownShortfallSeconds: TimeInterval { max(0, knownDemandSeconds - knownCapacitySeconds) }
}

struct DailyAvailability: Codable, Equatable {
    var day: String
    var windows: [PlanTimeRange]
}

enum ChildEstimateAccounting: String, Codable, Equatable {
    case usesParentEstimate
    case addsToParentEstimate
}

/// A parent is never allowed to hide unfinished work below it.  Callers must show
/// this choice before closing a parent that still has active children.
enum ActiveDescendantDisposition: Equatable {
    case completeDescendants
    case abandonDescendants
}

struct PlannedTask: Codable, Equatable, Identifiable {
    var id: String
    var sourceID: String?
    var title: String
    var originalEstimateSeconds: TimeInterval?
    var remainingEstimateSeconds: TimeInterval?
    var completedAt: Date?
    var abandonedAt: Date? = nil
    var order: Int?
    var deadline: Date?
    var prerequisiteTaskIDs: [String]
    var parentTaskID: String?
    var parentEstimateAccounting: ChildEstimateAccounting?
    var project: String?
    var context: String?
    var minimumChunkSeconds: TimeInterval?
    var categoryTags: [String]

    var needsEstimateRevision: Bool { completedAt == nil && abandonedAt == nil && remainingEstimateSeconds == 0 }
    var hasUnknownEstimate: Bool { originalEstimateSeconds == nil && remainingEstimateSeconds == nil }
}

struct TaskQueue: Equatable {
    var readyTasks: [PlannedTask]
    var deferredTasks: [PlannedTask]
    var selectedTaskID: String?
    var nextDeferredReturn: Date?
    var returnedForDeadline: [String]

    var suggestedTask: PlannedTask? { readyTasks.first }
    var selectableTasks: [PlannedTask] { readyTasks + deferredTasks }
}

extension WeeklyPlan {
    /// Forecasts unfinished task effort against supplied real focus capacity keyed by
    /// planning day. Tasks remain eligible when capacity is unknown; the result says
    /// so rather than assuming zero capacity or a zero estimate.
    func forecast(capacityByDay: [String: TimeInterval]) -> TaskForecast {
        let ordered = tasks.filter { $0.completedAt == nil && $0.abandonedAt == nil }.sorted {
            let left = $0.order ?? Int.max
            let right = $1.order ?? Int.max
            return left == right ? $0.id < $1.id : left < right
        }
        var capacity = capacityByDay.mapValues { max(0, $0) }
        var placements: [TaskForecast.Placement] = []
        var unplaced: [String] = []
        var unknown: [String] = []
        var conflicts: [TaskForecast.Conflict] = []
        let completed = Set(tasks.filter { $0.completedAt != nil }.map(\.id))

        for task in ordered {
            guard task.prerequisiteTaskIDs.allSatisfy(completed.contains) else {
                conflicts.append(.prerequisiteIncomplete(taskID: task.id))
                unplaced.append(task.id)
                continue
            }
            guard var remaining = task.remainingEstimateSeconds else {
                unknown.append(task.id)
                continue
            }
            let candidateDays = capacity.keys.sorted { left, right in
                if let deadline = task.deadline {
                    return left < right
                }
                let leftPreferred = allocations.contains { $0.taskID == task.id && $0.preferredDay == left }
                let rightPreferred = allocations.contains { $0.taskID == task.id && $0.preferredDay == right }
                return leftPreferred == rightPreferred ? left < right : leftPreferred
            }
            for day in candidateDays where remaining > 0 {
                if let deadline = task.deadline, let dayEnd = Self.forecastDayEnd(day, timeZoneIdentifier: timeZoneIdentifier), dayEnd > deadline { continue }
                let used = min(remaining, capacity[day] ?? 0)
                guard used > 0 else { continue }
                placements.append(.init(id: "\(task.id):\(day)", taskID: task.id, day: day, effortSeconds: used))
                capacity[day, default: 0] -= used
                remaining -= used
            }
            if remaining > 0 {
                unplaced.append(task.id)
                if task.deadline != nil { conflicts.append(.deadlineAtRisk(taskID: task.id)) }
            }
        }
        let knownDemand = ordered.compactMap(\.remainingEstimateSeconds).reduce(0, +)
        let knownCapacity = capacityByDay.values.reduce(0) { $0 + max(0, $1) }
        if knownDemand > knownCapacity { conflicts.append(.insufficientKnownCapacity(shortfallSeconds: knownDemand - knownCapacity)) }
        if availability == nil { conflicts.append(.missingFutureAvailability) }
        return TaskForecast(placements: placements, unplacedTaskIDs: unplaced, unknownEffortTaskIDs: unknown,
                            conflicts: conflicts, knownCapacitySeconds: knownCapacity, knownDemandSeconds: knownDemand)
    }

    private static func forecastDayEnd(_ day: String, timeZoneIdentifier: String?) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return calendar.dateInterval(of: .day, for: start)?.end
    }
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
    var selectedTaskID: String? = nil
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

private extension String {
    var nonEmptyPath: String { isEmpty ? "$" : self }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
