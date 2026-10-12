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
    var mode: WeeklyPlanImportMode
    var addedTaskIDs: [String]
    var changedDescriptionTaskIDs: [String]
    var sourceEstimateChanges: [String: SourceEstimateComparison]
}

struct SourceEstimateComparison: Equatable {
    var sourceOriginalSeconds: TimeInterval?
    var sourceRemainingSeconds: TimeInterval?
    var localRemainingSeconds: TimeInterval?
    var actualWorkSeconds: TimeInterval
}

enum WeeklyPlanImportMode: Equatable {
    case newWeeklyBatch
    case refreshCurrentPlan
}

enum WeeklyPlanImportConflict: Equatable {
    case sourceEstimateChanged(taskID: String)
    case sourceTaskMissing(taskID: String)
}

extension WeeklyPlan {
    /// Stages an external transfer document. An external source is a proposal, not
    /// a backup of app state: stable source IDs are required so a later refresh can
    /// reconcile by identity instead of guessing from a repeated title.
    func previewingExternalImport(_ source: WeeklyPlan) throws -> WeeklyPlanImportPreview {
        try source.validate()
        guard source.sourceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw PlanValidationError(path: "sourceID", message: "An imported plan needs a stable sourceID so a refresh can be reviewed safely.")
        }
        for (index, task) in source.tasks.enumerated() where task.sourceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw PlanValidationError(path: "tasks[\(index)].sourceID", message: "Imported tasks need a stable sourceID; matching by title is unsafe.")
        }
        // A source may propose first-import classification, but queue choice,
        // progress, hierarchy adjustments, and every other local decision remain
        // app-owned. Refreshes below deliberately retain the saved map instead.
        let proposedClassifications = source.localState.classifications
        var sourceWithoutClassification = source
        sourceWithoutClassification.localState.classifications = [:]
        guard sourceWithoutClassification.localState == PlanLocalState() else {
            throw PlanValidationError(path: "localState", message: "Import files describe proposed work only. Remove app-owned queue, work-history, and estimate-adjustment state.")
        }

        if source.sourceID == sourceID {
            return try previewingImport(source)
        }

        try validate()
        let existingSourceIDs = Set(tasks.compactMap(\.sourceID))
        let incomingSourceIDs = Set(source.tasks.compactMap(\.sourceID))
        let overlappingSourceIDs = existingSourceIDs.intersection(incomingSourceIDs)
        guard overlappingSourceIDs.isEmpty else {
            throw PlanValidationError(path: "sourceID", message: "This file identifies a new weekly source but reuses existing task sourceIDs. Refresh the original source, or give the replacement tasks new stable identities.")
        }
        let currentIDs = Set(tasks.map(\.id))
        var remappedIDs: [String: String] = [:]
        var incomingTasks = source.tasks
        for index in incomingTasks.indices {
            let oldID = incomingTasks[index].id
            let newID = currentIDs.contains(oldID) ? UUID().uuidString : oldID
            remappedIDs[oldID] = newID
            incomingTasks[index].id = newID
        }
        for index in incomingTasks.indices {
            incomingTasks[index].parentTaskID = incomingTasks[index].parentTaskID.flatMap { remappedIDs[$0] ?? $0 }
            incomingTasks[index].prerequisiteTaskIDs = incomingTasks[index].prerequisiteTaskIDs.map { remappedIDs[$0] ?? $0 }
        }

        var merged = source
        var priorTasks = tasks
        // Source ordering is only a first-import suggestion. Old source tasks now
        // live in carryover, so retaining their source order could collide with a
        // new snapshot's independent order values.
        for index in priorTasks.indices where priorTasks[index].sourceID != nil {
            priorTasks[index].order = nil
        }
        merged.tasks = priorTasks + incomingTasks
        merged.allocations = source.allocations.map { allocation in
            var remapped = allocation
            remapped.taskID = remappedIDs[allocation.taskID] ?? allocation.taskID
            return remapped
        }
        var retainedCommitments = fixedCommitments.filter { $0.sourceID == nil }
        let incomingCommitmentIDs = Set(source.fixedCommitments.map(\.id))
        for index in retainedCommitments.indices where incomingCommitmentIDs.contains(retainedCommitments[index].id) {
            retainedCommitments[index].id = UUID().uuidString
        }
        merged.fixedCommitments = source.fixedCommitments + retainedCommitments
        merged.localState = localState
        for (sourceTaskID, classification) in proposedClassifications {
            let taskID = remappedIDs[sourceTaskID] ?? sourceTaskID
            if merged.localState.classifications[taskID] == nil {
                merged.localState.classifications[taskID] = classification
            }
        }
        let oldUnfinished = tasks.filter { $0.completedAt == nil && $0.abandonedAt == nil }.map(\.id)
        merged.localState.carryoverTaskIDs = Array(Set(localState.carryoverTaskIDs).union(oldUnfinished)).sorted()
        if let selected = merged.localState.selectedTaskID, merged.localState.carryoverTaskIDs.contains(selected) {
            merged.localState.selectedTaskID = nil
        }
        let currentOrder = localState.taskOrder ?? tasks.sorted {
            let left = $0.order ?? Int.max
            let right = $1.order ?? Int.max
            return left == right ? $0.id < $1.id : left < right
        }.map(\.id)
        merged.localState.taskOrder = currentOrder + incomingTasks.map(\.id)
        try merged.validate()
        return WeeklyPlanImportPreview(
            mergedPlan: merged, conflicts: [], mode: .newWeeklyBatch,
            addedTaskIDs: incomingTasks.map(\.id), changedDescriptionTaskIDs: [], sourceEstimateChanges: [:]
        )
    }

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
        var addedTaskIDs: [String] = []
        var changedDescriptionTaskIDs: [String] = []
        var sourceEstimateChanges: [String: SourceEstimateComparison] = [:]

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
                addedTaskIDs.append(incomingTask.id)
                continue
            }

            remappedIDs[incomingTask.id] = existing.id
            var refreshed = existing
            // Source-owned descriptive fields may refresh. Execution state, local
            // hierarchy, order, progress, and estimates stay app-owned.
            if refreshed.title != incomingTask.title || refreshed.deadline != incomingTask.deadline ||
                refreshed.project != incomingTask.project || refreshed.context != incomingTask.context ||
                refreshed.minimumChunkSeconds != incomingTask.minimumChunkSeconds || refreshed.categoryTags != incomingTask.categoryTags {
                changedDescriptionTaskIDs.append(existing.id)
            }
            refreshed.title = incomingTask.title
            refreshed.deadline = incomingTask.deadline
            refreshed.project = incomingTask.project
            refreshed.context = incomingTask.context
            refreshed.minimumChunkSeconds = incomingTask.minimumChunkSeconds
            refreshed.categoryTags = incomingTask.categoryTags
            refreshed.prerequisiteTaskIDs = incomingTask.prerequisiteTaskIDs
            // Queue order is app-owned. Source order informs only a task's first import.
            if incomingTask.originalEstimateSeconds != existing.originalEstimateSeconds ||
                incomingTask.remainingEstimateSeconds != existing.remainingEstimateSeconds {
                conflicts.append(.sourceEstimateChanged(taskID: existing.id))
                sourceEstimateChanges[existing.id] = SourceEstimateComparison(
                    sourceOriginalSeconds: incomingTask.originalEstimateSeconds,
                    sourceRemainingSeconds: incomingTask.remainingEstimateSeconds,
                    localRemainingSeconds: existing.remainingEstimateSeconds,
                    actualWorkSeconds: actualWorkSeconds(for: existing.id)
                )
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
        let added = Set(addedTaskIDs)
        for index in mergedTasks.indices {
            mergedTasks[index].prerequisiteTaskIDs = mergedTasks[index].prerequisiteTaskIDs.map {
                remappedIDs[$0] ?? $0
            }
            if added.contains(mergedTasks[index].id) {
                mergedTasks[index].parentTaskID = mergedTasks[index].parentTaskID.flatMap { remappedIDs[$0] ?? $0 }
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
        return WeeklyPlanImportPreview(
            mergedPlan: merged, conflicts: conflicts, mode: .refreshCurrentPlan,
            addedTaskIDs: addedTaskIDs, changedDescriptionTaskIDs: changedDescriptionTaskIDs,
            sourceEstimateChanges: sourceEstimateChanges
        )
    }
}
