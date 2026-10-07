import XCTest
@testable import FocusRhythm

final class WeeklyPlanStoreTests: XCTestCase {
    func testStoreRoundTripsLocalChildrenProgressAndQueueState() throws {
        let store = makeStore()
        var plan = localPlan()
        try plan.addChild(task(id: "child", title: "Outline", estimate: 600), to: "parent", accounting: .usesParentEstimate, recordedAt: date(1_000))
        plan.localState.taskOrder = ["parent", "child"]
        plan.localState.deferrals = [TaskDeferral(taskID: "child", deferredAt: date(100), until: date(200))]
        plan.localState.workSegments = [segment(taskID: "child", start: 300, end: 600)]

        try store.save(plan)

        XCTAssertEqual(store.load(), plan)
    }

    func testThrowingUpdateLeavesPersistedCatalogUntouched() throws {
        let store = makeStore()
        let original = localPlan()
        try store.save(original)

        XCTAssertThrowsError(try store.update { plan in
            try plan.addChild(self.task(id: "too-large", title: "Too large", estimate: 7_201), to: "parent", accounting: .usesParentEstimate)
        })

        XCTAssertEqual(store.load(), original)
    }

    func testCorruptCatalogIsDiscardedRatherThanUsedAsAnEmptyPlan() {
        let suite = "WeeklyPlanStoreTests.corrupt.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "weekly-plan.catalog.v1")

        XCTAssertNil(UserDefaultsWeeklyPlanStore(defaults: defaults).load())
        XCTAssertNil(defaults.data(forKey: "weekly-plan.catalog.v1"))
    }

    func testStagedImportPreservesLocalChildProgressAndFlagsChangedParentEstimate() throws {
        var current = localPlan()
        current.tasks[0].sourceID = "source-parent"
        current.tasks[0].remainingEstimateSeconds = 5_400
        try current.addChild(task(id: "local-child", title: "Read chapter", estimate: 1_800), to: "parent", accounting: .usesParentEstimate)
        current.localState.taskOrder = ["parent", "local-child"]

        var incomingParent = task(id: "source-parent-id", title: "Updated title", estimate: 10_800)
        incomingParent.sourceID = "source-parent"
        incomingParent.deadline = date(10_000)
        let incoming = WeeklyPlan(id: "source-window", sourceID: "week-1", tasks: [incomingParent])

        let preview = try current.previewingImport(incoming)
        let parent = try XCTUnwrap(preview.mergedPlan.tasks.first { $0.id == "parent" })

        XCTAssertEqual(parent.title, "Updated title")
        XCTAssertEqual(parent.deadline, date(10_000))
        XCTAssertEqual(parent.remainingEstimateSeconds, 3_600)
        XCTAssertEqual(preview.mergedPlan.tasks.map(\.id), ["parent", "local-child"])
        XCTAssertEqual(preview.mergedPlan.localState.taskOrder, ["parent", "local-child"])
        XCTAssertEqual(preview.conflicts, [.sourceEstimateChanged(taskID: "parent")])
    }

    func testStagedImportRetainsSourceTaskMissingFromRefresh() throws {
        var current = localPlan()
        current.tasks[0].sourceID = "source-parent"
        let incoming = WeeklyPlan(id: "source-window", sourceID: "week-2", tasks: [])

        let preview = try current.previewingImport(incoming)

        XCTAssertEqual(preview.mergedPlan.tasks, current.tasks)
        XCTAssertEqual(preview.conflicts, [.sourceTaskMissing(taskID: "parent")])
    }

    private func makeStore() -> UserDefaultsWeeklyPlanStore {
        let suite = "WeeklyPlanStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return UserDefaultsWeeklyPlanStore(defaults: defaults)
    }

    private func localPlan() -> WeeklyPlan {
        WeeklyPlan(id: "catalog", tasks: [task(id: "parent", title: "Literature", estimate: 7_200)])
    }

    private func task(id: String, title: String, estimate: TimeInterval?) -> PlannedTask {
        PlannedTask(id: id, sourceID: nil, title: title, originalEstimateSeconds: estimate,
                    remainingEstimateSeconds: estimate, completedAt: nil, order: nil, deadline: nil,
                    prerequisiteTaskIDs: [], parentTaskID: nil, parentEstimateAccounting: nil,
                    project: nil, context: nil, minimumChunkSeconds: nil, categoryTags: [])
    }

    private func segment(taskID: String, start: TimeInterval, end: TimeInterval) -> TaskWorkSegment {
        let focus = ScheduledInterval(
            kind: .focus,
            startDate: date(start),
            endDate: date(end + 60),
            isAnchored: false
        )
        return try! TaskWorkSegment(
            taskID: taskID,
            runID: UUID(),
            focusInterval: focus,
            start: date(start),
            end: date(end)
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}
