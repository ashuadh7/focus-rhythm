import Foundation

/// The durable boundary for task data. Planning-window data is optional, so a catalog
/// containing only locally created tasks uses the same store as an imported plan.
protocol WeeklyPlanStoring {
    func load() -> WeeklyPlan?
    func save(_ plan: WeeklyPlan) throws
    func clear()
}

final class UserDefaultsWeeklyPlanStore: WeeklyPlanStoring {
    private static let key = "weekly-plan.catalog.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WeeklyPlan? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        do {
            return try WeeklyPlanJSON.decode(data)
        } catch {
            // A corrupt catalog must never be handed to execution code as an empty,
            // apparently valid plan. Remove only the unreadable snapshot.
            defaults.removeObject(forKey: Self.key)
            return nil
        }
    }

    func save(_ plan: WeeklyPlan) throws {
        // Encoding and validation finish before the previous snapshot is replaced.
        let data = try WeeklyPlanJSON.encode(plan)
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Applies a complete, validated replacement. A throwing mutation leaves the
    /// persisted catalog untouched, which keeps multi-field changes atomic.
    @discardableResult
    func update(_ mutate: (inout WeeklyPlan) throws -> Void) throws -> WeeklyPlan {
        guard var candidate = load() else {
            throw PlanStoreError.noSavedPlan
        }
        try mutate(&candidate)
        try save(candidate)
        return candidate
    }
}

enum PlanStoreError: Error, Equatable, LocalizedError {
    case noSavedPlan
    case unrelatedTaskIDCollision(String)

    var errorDescription: String? {
        switch self {
        case .noSavedPlan: return "No saved task catalog is available."
        case let .unrelatedTaskIDCollision(id): return "Imported task identity '\(id)' conflicts with a local task."
        }
    }
}

/// A reimport is staged for review rather than persisted as part of decoding. This
/// keeps source changes from erasing app-owned work, completion, decomposition, or
/// queue choices.
struct WeeklyPlanImportPreview: Equatable {
    var mergedPlan: WeeklyPlan
    var conflicts: [WeeklyPlanImportConflict]
}

enum WeeklyPlanImportConflict: Equatable {
    case sourceEstimateChanged(taskID: String)
    case sourceTaskMissing(taskID: String)
}

extension WeeklyPlan {
    /// Prepares a source refresh without changing the saved catalog. Existing source
    /// tasks retain their app-owned IDs and local execution state. Changed estimates
    /// deliberately remain unchanged until a caller presents and resolves the conflict.
    func previewingImport(_ incoming: WeeklyPlan) throws -> WeeklyPlanImportPreview {
        try validate()
        try incoming.validate()

        let existingBySourceID = Dictionary(uniqueKeysWithValues: tasks.compactMap { task in
            task.sourceID.map { ($0, task) }
        })
        let existingIDs = Set(tasks.map(\.id))
        var incomingSourceIDs = Set<String>()
        var remappedIDs: [String: String] = [:]
        var mergedTasks: [PlannedTask] = []
        var conflicts: [WeeklyPlanImportConflict] = []

        for incomingTask in incoming.tasks {
            if let sourceID = incomingTask.sourceID {
                incomingSourceIDs.insert(sourceID)
            }

            guard let sourceID = incomingTask.sourceID,
                  let existing = existingBySourceID[sourceID]
            else {
                guard !existingIDs.contains(incomingTask.id) else {
                    throw PlanStoreError.unrelatedTaskIDCollision(incomingTask.id)
                }
                mergedTasks.append(incomingTask)
                remappedIDs[incomingTask.id] = incomingTask.id
                continue
            }

            remappedIDs[incomingTask.id] = existing.id
            var refreshed = existing
            // Source-owned descriptive fields may refresh. Execution state, local
            // hierarchy, order, progress, and estimates stay app-owned.
            refreshed.title = incomingTask.title
            refreshed.deadline = incomingTask.deadline
            refreshed.project = incomingTask.project
            refreshed.context = incomingTask.context
            refreshed.minimumChunkSeconds = incomingTask.minimumChunkSeconds
            refreshed.categoryTags = incomingTask.categoryTags
            refreshed.prerequisiteTaskIDs = incomingTask.prerequisiteTaskIDs
            refreshed.order = incomingTask.order
            if incomingTask.originalEstimateSeconds != existing.originalEstimateSeconds ||
                incomingTask.remainingEstimateSeconds != existing.remainingEstimateSeconds {
                conflicts.append(.sourceEstimateChanged(taskID: existing.id))
            }
            mergedTasks.append(refreshed)
        }

        for task in tasks where task.sourceID != nil && !incomingSourceIDs.contains(task.sourceID!) {
            conflicts.append(.sourceTaskMissing(taskID: task.id))
            mergedTasks.append(task)
        }
        mergedTasks.append(contentsOf: tasks.filter { $0.sourceID == nil })

        // Incoming dependency IDs refer to the incoming snapshot. Matched source
        // tasks retain their app IDs, so remap before validation.
        for index in mergedTasks.indices {
            mergedTasks[index].prerequisiteTaskIDs = mergedTasks[index].prerequisiteTaskIDs.map {
                remappedIDs[$0] ?? $0
            }
        }

        var merged = self
        merged.sourceID = incoming.sourceID
        merged.timeZoneIdentifier = incoming.timeZoneIdentifier
        merged.horizon = incoming.horizon
        merged.availability = incoming.availability
        merged.fixedCommitments = incoming.fixedCommitments
        merged.tasks = mergedTasks
        merged.allocations = incoming.allocations.map { allocation in
            var remapped = allocation
            remapped.taskID = remappedIDs[allocation.taskID] ?? allocation.taskID
            return remapped
        }
        try merged.validate()
        return WeeklyPlanImportPreview(mergedPlan: merged, conflicts: conflicts)
    }
}
