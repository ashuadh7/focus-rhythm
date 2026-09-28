import XCTest
@testable import FocusRhythm

final class WeeklyPlanTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testLocalRootTaskNeedsNoSourceWindowOrEstimate() throws {
        let task = makeTask(id: "read", title: "Read related work", estimate: nil)
        let plan = WeeklyPlan(id: "local-tasks", tasks: [task])

        try plan.validate()
        XCTAssertNil(plan.sourceID)
        XCTAssertNil(plan.horizon)
        XCTAssertTrue(plan.hasUnknownRemainingEffort)
        XCTAssertEqual(plan.remainingEffortSeconds, 0)
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)
    }

    func testChildUsingExistingEstimateKeepsTotalAtTwoAndAHalfHours() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "literature", title: "Literature review", estimate: 2.5 * 3600)])

        try plan.addChild(makeTask(id: "branch-x", title: "Review X", estimate: 3600), to: "literature", accounting: .usesParentEstimate, recordedAt: now)

        XCTAssertEqual(task("literature", in: plan).remainingEstimateSeconds, 1.5 * 3600)
        XCTAssertEqual(task("branch-x", in: plan).remainingEstimateSeconds, 3600)
        XCTAssertEqual(plan.originalEffortSeconds, 2.5 * 3600)
        XCTAssertEqual(plan.remainingEffortSeconds, 2.5 * 3600)
        XCTAssertEqual(plan.localState.estimateAdjustments.single?.accounting, .usesParentEstimate)
        XCTAssertEqual(plan.descendantIDs(of: "literature"), ["branch-x"])
    }

    func testChildAddingEstimateIncreasesTotalToThreeAndAHalfHours() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "literature", title: "Literature review", estimate: 2.5 * 3600)])

        try plan.addChild(makeTask(id: "branch-x", title: "Review X", estimate: 3600), to: "literature", accounting: .addsToParentEstimate, recordedAt: now)

        XCTAssertEqual(task("literature", in: plan).remainingEstimateSeconds, 2.5 * 3600)
        XCTAssertEqual(plan.originalEffortSeconds, 3.5 * 3600)
        XCTAssertEqual(plan.remainingEffortSeconds, 3.5 * 3600)
        XCTAssertEqual(plan.localState.estimateAdjustments.single?.amountSeconds, 3600)
    }

    func testUnknownParentCanGainAConcreteChildWithoutInventingParentEffort() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "literature", title: "Literature review", estimate: nil)])

        try plan.addChild(makeTask(id: "branch-x", title: "Review X", estimate: 3600), to: "literature", accounting: .usesParentEstimate, recordedAt: now)

        XCTAssertNil(task("literature", in: plan).remainingEstimateSeconds)
        XCTAssertEqual(plan.remainingEffortSeconds, 3600)
        XCTAssertTrue(plan.hasUnknownRemainingEffort)
        XCTAssertEqual(task("branch-x", in: plan).parentEstimateAccounting, .usesParentEstimate)
    }

    func testChildCreationDoesNotPartiallyMutateWhenItExceedsParentEstimate() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Parent", estimate: 1800)])
        let original = plan

        XCTAssertThrowsError(try plan.addChild(makeTask(id: "child", title: "Child", estimate: 3600), to: "parent", accounting: .usesParentEstimate, recordedAt: now))
        XCTAssertEqual(plan, original)
    }

    func testNestedChildrenAndActualWorkRollUpWithoutChangingGlobalTotal() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3 * 3600)])
        try plan.addChild(makeTask(id: "child", title: "Child", estimate: 3600), to: "parent", accounting: .usesParentEstimate, recordedAt: now)
        try plan.addChild(makeTask(id: "grandchild", title: "Grandchild", estimate: 600), to: "child", accounting: .usesParentEstimate, recordedAt: now)
        XCTAssertEqual(plan.remainingEffortSeconds, 3 * 3600)
        XCTAssertEqual(plan.descendantIDs(of: "parent"), ["child", "grandchild"])
    }

    func testRejectsContainmentCyclesAndMissingAccountingRecords() throws {
        var parent = makeTask(id: "parent", title: "Parent", estimate: 3600)
        parent.parentTaskID = "child"
        parent.parentEstimateAccounting = .usesParentEstimate
        let child = makeChild(id: "child", title: "Child", parentID: "parent", estimate: 600, accounting: .usesParentEstimate)
        var state = PlanLocalState()
        state.estimateAdjustments = [
            adjustment(parent: "child", child: "parent", accounting: .usesParentEstimate),
            adjustment(parent: "parent", child: "child", accounting: .usesParentEstimate)
        ]
        let plan = WeeklyPlan(id: "local", tasks: [parent, child], localState: state)
        assertInvalid(plan, path: "tasks.parentTaskID")

        let childWithoutRecord = makeChild(id: "child", title: "Child", parentID: "parent", estimate: 600, accounting: .usesParentEstimate)
        assertInvalid(WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3600), childWithoutRecord]), path: "tasks.parentTaskID")
    }

    func testRejectsInvalidEstimatePairsAndParentReferences() {
        var halfKnown = makeTask(id: "task", title: "Task", estimate: 3600)
        halfKnown.remainingEstimateSeconds = nil
        assertInvalid(WeeklyPlan(id: "local", tasks: [halfKnown]), path: "tasks[0].estimate")

        var orphan = makeTask(id: "task", title: "Task", estimate: 3600)
        orphan.parentTaskID = "missing"
        orphan.parentEstimateAccounting = .addsToParentEstimate
        assertInvalid(WeeklyPlan(id: "local", tasks: [orphan]), path: "tasks[0].parentTaskID")
    }

    func testChildAccountingHistoryKeepsTheLatestChoice() throws {
        let parent = makeTask(id: "parent", title: "Parent", estimate: 2.5 * 3600)
        let child = makeChild(id: "child", title: "Child", parentID: "parent", estimate: 3600, accounting: .addsToParentEstimate)
        var state = PlanLocalState()
        state.estimateAdjustments = [
            TaskEstimateAdjustment(parentTaskID: "parent", childTaskID: "child", accounting: .usesParentEstimate, amountSeconds: 3600, recordedAt: now),
            TaskEstimateAdjustment(parentTaskID: "parent", childTaskID: "child", accounting: .addsToParentEstimate, amountSeconds: 3600, recordedAt: now.addingTimeInterval(1))
        ]

        try WeeklyPlan(id: "local", tasks: [parent, child], localState: state).validate()
    }

    func testImportedFixtureStillRoundTripsAndCoexistsWithLocalTask() throws {
        var plan = try fixture()
        plan.tasks.append(makeTask(id: "local-follow-up", title: "Local follow-up", estimate: nil))
        plan.localState.taskOrder = plan.tasks.map(\.id)

        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)
        XCTAssertEqual(plan.actualWorkSeconds(for: "grading"), 40 * 60)
        XCTAssertTrue(plan.hasUnknownRemainingEffort)
    }

    func testPlanningDataRequiresACompletePlanningWindow() {
        let allocation = PlannedAllocation(id: "today", taskID: "task", preferredDay: "2026-09-28", suggestedTime: nil, plannedEffortSeconds: nil)
        assertInvalid(WeeklyPlan(id: "local", tasks: [makeTask(id: "task", title: "Task", estimate: nil)], allocations: [allocation]), path: "allocations")
    }

    func testUnknownVersionAndInvalidDatesAreRejected() {
        XCTAssertThrowsError(try WeeklyPlanJSON.decode(Data(#"{"schemaVersion":2}"#.utf8)))
        XCTAssertFalse(WeeklyPlan.isValidDay("2026-02-29"))
        XCTAssertTrue(WeeklyPlan.isValidDay("2024-02-29"))
    }

    private func fixture() throws -> WeeklyPlan {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "weekly-plan-v1", withExtension: "json"))
        return try WeeklyPlanJSON.decode(Data(contentsOf: url))
    }

    private func makeTask(id: String, title: String, estimate: TimeInterval?) -> PlannedTask {
        PlannedTask(id: id, sourceID: nil, title: title, originalEstimateSeconds: estimate,
                    remainingEstimateSeconds: estimate, completedAt: nil, order: nil, deadline: nil,
                    prerequisiteTaskIDs: [], parentTaskID: nil, parentEstimateAccounting: nil,
                    project: nil, context: nil, minimumChunkSeconds: nil, categoryTags: [])
    }

    private func makeChild(id: String, title: String, parentID: String, estimate: TimeInterval?, accounting: ChildEstimateAccounting) -> PlannedTask {
        var task = makeTask(id: id, title: title, estimate: estimate)
        task.parentTaskID = parentID
        task.parentEstimateAccounting = accounting
        return task
    }

    private func adjustment(parent: String, child: String, accounting: ChildEstimateAccounting) -> TaskEstimateAdjustment {
        TaskEstimateAdjustment(parentTaskID: parent, childTaskID: child, accounting: accounting, amountSeconds: 600, recordedAt: now)
    }

    private func task(_ id: String, in plan: WeeklyPlan) -> PlannedTask {
        plan.tasks.first { $0.id == id }!
    }

    private func assertInvalid(_ plan: WeeklyPlan, path: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try plan.validate(), file: file, line: line) { error in
            XCTAssertTrue((error as? PlanValidationError)?.path.hasPrefix(path) == true, "\(error)", file: file, line: line)
        }
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
