import Foundation

extension WeeklyPlan {
    /// Validates the contract, not feasibility. Overdue tasks, overlapping commitments,
    /// and suggestions exceeding available capacity must survive for later review.
    func validate() throws {
        func require(_ condition: Bool, _ path: String, _ message: String) throws {
            if !condition { throw PlanValidationError(path: path, message: message) }
        }
        func nonempty(_ value: String, _ path: String) throws {
            try require(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, path, "Must not be blank.")
        }
        func effort(_ value: TimeInterval, _ path: String) throws {
            try require(value.isFinite && value >= 0, path, "Effort must be finite, nonnegative seconds.")
        }
        func date(_ value: Date, _ path: String) throws {
            try require(value.timeIntervalSinceReferenceDate.isFinite, path, "Timestamp must be finite.")
        }
        func range(_ value: PlanTimeRange, _ path: String) throws {
            try date(value.start, "\(path).start")
            try date(value.end, "\(path).end")
            try require(value.start < value.end, path, "End must be after start.")
        }
        func day(_ value: String, _ path: String) throws {
            try require(Self.isValidDay(value), path, "Expected a real Gregorian date in YYYY-MM-DD format.")
        }
        func unique(_ values: [String], _ path: String) throws {
            var seen = Set<String>()
            for (index, value) in values.enumerated() {
                try nonempty(value, "\(path)[\(index)]")
                try require(seen.insert(value).inserted, "\(path)[\(index)]", "Duplicate identity '\(value)'.")
            }
        }

        try require(schemaVersion == Self.currentSchemaVersion, "schemaVersion", "Unsupported version \(schemaVersion); expected 1.")
        try nonempty(id, "id")
        try nonempty(sourceID, "sourceID")
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw PlanValidationError(path: "timeZoneIdentifier", message: "Unknown timezone '\(timeZoneIdentifier)'.")
        }
        try day(horizon.startDay, "horizon.startDay")
        try day(horizon.endDayExclusive, "horizon.endDayExclusive")
        try require(horizon.startDay < horizon.endDayExclusive, "horizon", "End day must be after start day (exclusive).")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func dayBounds(_ value: String) throws -> DateInterval {
            let parts = value.split(separator: "-").compactMap { Int($0) }
            guard let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  calendar.component(.year, from: start) == parts[0],
                  calendar.component(.month, from: start) == parts[1],
                  calendar.component(.day, from: start) == parts[2],
                  let bounds = calendar.dateInterval(of: .day, for: start) else {
                throw PlanValidationError(path: "day", message: "\(value) does not exist in \(timeZoneIdentifier).")
            }
            return bounds
        }
        if let availability {
            try unique(availability.map(\.day), "availability.day")
            for (index, entry) in availability.enumerated() {
                let path = "availability[\(index)]"
                try day(entry.day, "\(path).day")
                try require(entry.day >= horizon.startDay && entry.day < horizon.endDayExclusive,
                            "\(path).day", "Availability must fall within the plan horizon.")
                let bounds = try dayBounds(entry.day)
                for (windowIndex, window) in entry.windows.enumerated() {
                    let windowPath = "\(path).windows[\(windowIndex)]"
                    try range(window, windowPath)
                    try require(window.start >= bounds.start && window.end <= bounds.end,
                                windowPath, "Window must fit within its local day; split overnight availability at midnight.")
                }
                let sorted = entry.windows.sorted { $0.start < $1.start }
                for (first, next) in zip(sorted, sorted.dropFirst()) {
                    try require(first.end <= next.start, "\(path).windows", "Availability windows must not overlap.")
                }
            }
        }

        try unique(tasks.map(\.id), "tasks.id")
        try unique(tasks.compactMap(\.sourceID), "tasks.sourceID")
        let taskIDs = Set(tasks.map(\.id))
        var orders = Set<Int>()
        for (index, task) in tasks.enumerated() {
            let path = "tasks[\(index)]"
            try nonempty(task.title, "\(path).title")
            try effort(task.originalEstimateSeconds, "\(path).originalEstimateSeconds")
            try effort(task.remainingEstimateSeconds, "\(path).remainingEstimateSeconds")
            if let chunk = task.minimumChunkSeconds { try effort(chunk, "\(path).minimumChunkSeconds") }
            if let completed = task.completedAt { try date(completed, "\(path).completedAt") }
            if let deadline = task.deadline { try date(deadline, "\(path).deadline") }
            try require(task.order >= 0 && orders.insert(task.order).inserted, "\(path).order", "Order must be nonnegative and unique across tasks.")
            try unique(task.prerequisiteTaskIDs, "\(path).prerequisiteTaskIDs")
            for prerequisite in task.prerequisiteTaskIDs {
                try require(taskIDs.contains(prerequisite), "\(path).prerequisiteTaskIDs", "Unknown task '\(prerequisite)'. Retain referenced completed tasks.")
            }
            for (tagIndex, tag) in task.categoryTags.enumerated() { try nonempty(tag, "\(path).categoryTags[\(tagIndex)]") }
        }
        // Kahn traversal avoids recursion depth limits for externally prepared plans.
        var remaining = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.prerequisiteTaskIDs.count) })
        var dependents: [String: [String]] = [:]
        for task in tasks {
            for prerequisite in task.prerequisiteTaskIDs { dependents[prerequisite, default: []].append(task.id) }
        }
        var ready = tasks.filter { $0.prerequisiteTaskIDs.isEmpty }.map(\.id)
        var cursor = 0
        while cursor < ready.count {
            let id = ready[cursor]
            cursor += 1
            for dependent in dependents[id, default: []] {
                remaining[dependent, default: 0] -= 1
                if remaining[dependent] == 0 { ready.append(dependent) }
            }
        }
        if ready.count != tasks.count {
            let blocked = tasks.filter { remaining[$0.id, default: 0] > 0 }.map(\.id).joined(separator: ", ")
            throw PlanValidationError(path: "tasks.prerequisiteTaskIDs", message: "Dependency cycle blocks: \(blocked).")
        }

        try unique(allocations.map(\.id), "allocations.id")
        for (index, allocation) in allocations.enumerated() {
            let path = "allocations[\(index)]"
            try require(taskIDs.contains(allocation.taskID), "\(path).taskID", "Unknown task '\(allocation.taskID)'.")
            try day(allocation.preferredDay, "\(path).preferredDay")
            if let suggestion = allocation.suggestedTime {
                try range(suggestion, "\(path).suggestedTime")
                let bounds = try dayBounds(allocation.preferredDay)
                try require(suggestion.start >= bounds.start && suggestion.end <= bounds.end,
                            "\(path).suggestedTime", "Suggested time must fit its preferred local day.")
            }
            if let amount = allocation.plannedEffortSeconds { try effort(amount, "\(path).plannedEffortSeconds") }
        }
        try unique(fixedCommitments.map(\.id), "fixedCommitments.id")
        try unique(fixedCommitments.compactMap(\.sourceID), "fixedCommitments.sourceID")
        for (index, commitment) in fixedCommitments.enumerated() {
            try nonempty(commitment.title, "fixedCommitments[\(index)].title")
            try range(commitment.time, "fixedCommitments[\(index)].time")
        }

        if let order = localState.taskOrder {
            try unique(order, "localState.taskOrder")
            try require(Set(order) == taskIDs, "localState.taskOrder", "Local order must contain every task ID exactly once, including completed tasks.")
        }
        try unique(localState.deferrals.map(\.taskID), "localState.deferrals.taskID")
        for (index, deferral) in localState.deferrals.enumerated() {
            let path = "localState.deferrals[\(index)]"
            try require(taskIDs.contains(deferral.taskID), "\(path).taskID", "Unknown task '\(deferral.taskID)'.")
            try range(PlanTimeRange(start: deferral.deferredAt, end: deferral.until), path)
        }
        try unique(localState.workSegments.map { $0.id.uuidString }, "localState.workSegments.id")
        for (index, segment) in localState.workSegments.enumerated() {
            let path = "localState.workSegments[\(index)]"
            if let taskID = segment.taskID {
                try require(taskIDs.contains(taskID), "\(path).taskID", "Unknown task '\(taskID)'.")
            }
            try range(segment.time, "\(path).time")
        }
        let segments = localState.workSegments.sorted { $0.time.start < $1.time.start }
        for (first, next) in zip(segments, segments.dropFirst()) {
            try require(first.time.end <= next.time.start, "localState.workSegments", "Actual work overlaps at segment '\(next.id)'; time may be credited only once.")
        }
    }

    /// The owning run supplies the schedule when restoring or accepting local work.
    /// The weekly snapshot alone cannot establish that an external UUID is a focus interval.
    func validateWorkSegments(in schedule: GeneratedDailySchedule, runID: UUID) throws {
        try validate()
        let segments = localState.workSegments.filter { $0.runID == runID }
        var credited: [UUID: TimeInterval] = [:]
        for segment in segments {
            guard let interval = schedule.intervals.first(where: { $0.id == segment.focusIntervalID }),
                  interval.kind == .focus,
                  segment.time.start >= interval.startDate, segment.time.end <= interval.endDate else {
                throw PlanValidationError(path: "localState.workSegments", message: "Segment '\(segment.id)' must reference and fit a focus interval in its run.")
            }
            credited[interval.id, default: 0] += segment.duration
            guard credited[interval.id, default: 0] <= interval.duration else {
                throw PlanValidationError(path: "localState.workSegments", message: "Segments exceed credited focus for interval '\(interval.id)'.")
            }
        }
    }

    static func isValidDay(_ value: String) -> Bool {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] >= 1 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return false }
        return calendar.component(.year, from: date) == parts[0]
            && calendar.component(.month, from: date) == parts[1]
            && calendar.component(.day, from: date) == parts[2]
    }
}
