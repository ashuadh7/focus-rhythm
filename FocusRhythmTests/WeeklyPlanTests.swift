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

    func testLocalTaskCreationUsesStableAppIdentityAndAppendsToQueue() throws {
        var plan = WeeklyPlan(id: "local-tasks", tasks: [])
        let id = try plan.addLocalTask(title: "  Draft outline  ", estimateSeconds: 45 * 60,
                                       project: "Essay", categoryTags: ["writing", "  "])

        let task = try XCTUnwrap(plan.tasks.first { $0.id == id })
        XCTAssertEqual(task.title, "Draft outline")
        XCTAssertNil(task.sourceID)
        XCTAssertEqual(task.remainingEstimateSeconds, 45 * 60)
        XCTAssertEqual(task.project, "Essay")
        XCTAssertEqual(task.categoryTags, ["writing"])
        XCTAssertEqual(plan.localState.taskOrder, [id])
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)
    }

    func testUnknownEffortLocalTaskIsSelectableButZeroEffortRequestsRevision() throws {
        var plan = WeeklyPlan(id: "local-tasks", tasks: [])
        let unknown = try plan.addLocalTask(title: "Investigate", estimateSeconds: nil)
        let zero = try plan.addLocalTask(title: "Revise estimate", estimateSeconds: 0)

        XCTAssertEqual(plan.taskQueue(at: now).readyTasks.map(\.id), [unknown])
        XCTAssertTrue(try XCTUnwrap(plan.tasks.first { $0.id == zero }).needsEstimateRevision)
    }

    func testUrgentTaskPreservesAndResumesInterruptedTaskAcrossRoundTrip() throws {
        var plan = WeeklyPlan(id: "local-tasks", tasks: [
            makeTask(id: "grading", title: "Grading", estimate: 3_600),
            makeTask(id: "email", title: "Urgent email", estimate: nil)
        ], localState: PlanLocalState(selectedTaskID: "grading"))

        try plan.beginUrgentTask("email")

        XCTAssertEqual(plan.localState.selectedTaskID, "email")
        XCTAssertEqual(plan.localState.interruptedTaskIDs, ["grading"])
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)

        XCTAssertEqual(try plan.resumeInterruptedTask(), "grading")
        XCTAssertEqual(plan.localState.selectedTaskID, "grading")
        XCTAssertTrue(plan.localState.interruptedTaskIDs.isEmpty)
    }

    func testNestedUrgentTasksResumeInReverseOrder() throws {
        var plan = WeeklyPlan(id: "local-tasks", tasks: [
            makeTask(id: "grading", title: "Grading", estimate: 3_600),
            makeTask(id: "email", title: "Email", estimate: nil),
            makeTask(id: "call", title: "Call", estimate: nil)
        ], localState: PlanLocalState(selectedTaskID: "grading"))

        try plan.beginUrgentTask("email")
        try plan.beginUrgentTask("call")

        XCTAssertEqual(plan.localState.interruptedTaskIDs, ["grading", "email"])
        XCTAssertEqual(try plan.resumeInterruptedTask(), "email")
        XCTAssertEqual(try plan.resumeInterruptedTask(), "grading")
    }

    func testCompletingInterruptedTaskRemovesItFromResumeStack() throws {
        var plan = WeeklyPlan(id: "local-tasks", tasks: [
            makeTask(id: "grading", title: "Grading", estimate: 3_600),
            makeTask(id: "email", title: "Urgent email", estimate: nil)
        ], localState: PlanLocalState(selectedTaskID: "grading"))

        try plan.beginUrgentTask("email")
        try plan.markTaskCompleted("grading", at: now)

        XCTAssertTrue(plan.localState.interruptedTaskIDs.isEmpty)
        XCTAssertNil(try plan.resumeInterruptedTask())
    }

    func testResumeDiscardsLegacyTerminalInterruptedTasks() throws {
        var completed = makeTask(id: "done", title: "Done", estimate: nil)
        completed.completedAt = now
        var plan = WeeklyPlan(id: "local-tasks", tasks: [
            completed,
            makeTask(id: "next", title: "Next", estimate: nil)
        ], localState: PlanLocalState(interruptedTaskIDs: ["next", "done"]))

        XCTAssertEqual(try plan.resumeInterruptedTask(), "next")
        XCTAssertEqual(plan.localState.selectedTaskID, "next")
        XCTAssertTrue(plan.localState.interruptedTaskIDs.isEmpty)
    }

    func testEditAndAbandonLocalTaskPreserveHistoryButRemoveItFromQueue() throws {
        var plan = WeeklyPlan(id: "local-tasks", tasks: [])
        let id = try plan.addLocalTask(title: "Old title", estimateSeconds: nil)
        try plan.editLocalTask(id, title: "New title", estimateSeconds: 600, deadline: now,
                               project: "Project", context: "Desk", categoryTags: ["admin"])
        try plan.abandonLocalTask(id, at: now.addingTimeInterval(60))

        let task = try XCTUnwrap(plan.tasks.first { $0.id == id })
        XCTAssertEqual(task.title, "New title")
        XCTAssertEqual(task.remainingEstimateSeconds, 600)
        XCTAssertNotNil(task.abandonedAt)
        XCTAssertFalse(plan.taskQueue(at: now).selectableTasks.contains { $0.id == id })
    }

    func testLocalCreationCanAtomicallyCreateAChildWithParentAccounting() throws {
        var plan = WeeklyPlan(id: "local-tasks", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3_600)])
        let child = try plan.addLocalTask(title: "Child", estimateSeconds: 600, parentID: "parent", accounting: .usesParentEstimate, recordedAt: now)

        XCTAssertEqual(task("parent", in: plan).remainingEstimateSeconds, 3_000)
        XCTAssertEqual(task(child, in: plan).parentTaskID, "parent")
        XCTAssertEqual(plan.localState.estimateAdjustments.count, 1)
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

    func testEditingChildEstimateAndAccountingReallocatesKnownWorkAtomically() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3_600)])
        let childID = try plan.addLocalTask(title: "Child", estimateSeconds: 600, parentID: "parent", accounting: .usesParentEstimate, recordedAt: now)

        try plan.editLocalTask(childID, title: "Child", estimateSeconds: 900, deadline: nil,
                               project: nil, context: nil, categoryTags: [], parentID: "parent",
                               accounting: .usesParentEstimate, recordedAt: now)
        XCTAssertEqual(task("parent", in: plan).remainingEstimateSeconds, 2_700)
        XCTAssertEqual(plan.remainingEffortSeconds, 3_600)

        try plan.editLocalTask(childID, title: "Child", estimateSeconds: 900, deadline: nil,
                               project: nil, context: nil, categoryTags: [], parentID: "parent",
                               accounting: .addsToParentEstimate, recordedAt: now)
        XCTAssertEqual(task("parent", in: plan).remainingEstimateSeconds, 3_600)
        XCTAssertEqual(plan.remainingEffortSeconds, 4_500)
        XCTAssertEqual(plan.localState.estimateAdjustments.count, 3)
        XCTAssertEqual(plan.localState.estimateAdjustments.last?.accounting, .addsToParentEstimate)
    }

    func testEditingChildRejectsCycleWithoutMutatingPlan() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3_600)])
        let childID = try plan.addLocalTask(title: "Child", estimateSeconds: 600, parentID: "parent", accounting: .usesParentEstimate, recordedAt: now)
        let original = plan

        XCTAssertThrowsError(try plan.editLocalTask("parent", title: "Parent", estimateSeconds: 3_000, deadline: nil,
                                                     project: nil, context: nil, categoryTags: [], parentID: childID,
                                                     accounting: .usesParentEstimate, recordedAt: now))
        XCTAssertEqual(plan, original)
    }

    func testParentCompletionAndAbandonmentRequireAnExplicitDescendantDecision() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3_600)])
        _ = try plan.addLocalTask(title: "Child", estimateSeconds: 600, parentID: "parent", accounting: .usesParentEstimate, recordedAt: now)

        XCTAssertThrowsError(try plan.markTaskCompleted("parent", at: now))
        try plan.markTaskCompleted("parent", at: now, descendantDisposition: .completeDescendants)
        XCTAssertTrue(plan.tasks.allSatisfy { $0.completedAt == now })

        var another = WeeklyPlan(id: "another", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3_600)])
        _ = try another.addLocalTask(title: "Child", estimateSeconds: 600, parentID: "parent", accounting: .usesParentEstimate, recordedAt: now)
        XCTAssertThrowsError(try another.abandonLocalTask("parent", at: now))
        try another.abandonLocalTask("parent", at: now, descendantDisposition: .abandonDescendants)
        XCTAssertTrue(another.tasks.allSatisfy { $0.abandonedAt == now })
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

    func testForecastPlacesKnownWorkOnceAndReportsUnknownAndOverflow() throws {
        var parent = makeTask(id: "parent", title: "Parent", estimate: 9_000)
        parent.order = 0
        var child = makeTask(id: "child", title: "Child", estimate: 3_600)
        child.order = 1
        var unknown = makeTask(id: "unknown", title: "Unknown", estimate: nil)
        unknown.order = 2
        var plan = WeeklyPlan(id: "local", tasks: [parent, unknown])
        try plan.addChild(child, to: "parent", accounting: .usesParentEstimate, recordedAt: now)

        let forecast = plan.forecast(capacityByDay: ["2026-10-12": 7_200])

        XCTAssertEqual(forecast.knownDemandSeconds, 9_000)
        XCTAssertEqual(forecast.knownShortfallSeconds, 1_800)
        XCTAssertEqual(forecast.placements.reduce(0) { $0 + $1.effortSeconds }, 7_200)
        XCTAssertEqual(forecast.unknownEffortTaskIDs, ["unknown"])
        XCTAssertTrue(forecast.conflicts.contains(.insufficientKnownCapacity(shortfallSeconds: 1_800)))
    }

    func testForecastKeepsBlockedPrerequisiteUnplaced() {
        var task = makeTask(id: "dependent", title: "Dependent", estimate: 3_600)
        task.prerequisiteTaskIDs = ["first"]
        let first = makeTask(id: "first", title: "First", estimate: 3_600)
        let forecast = WeeklyPlan(id: "local", tasks: [first, task]).forecast(capacityByDay: ["2026-10-12": 14_400])

        XCTAssertTrue(forecast.unplacedTaskIDs.contains("dependent"))
        XCTAssertTrue(forecast.conflicts.contains(.prerequisiteIncomplete(taskID: "dependent")))
    }

    func testQueueOrdersTasksAndKeepsNotNowTaskOutOfImmediateSuggestion() throws {
        var first = makeTask(id: "first", title: "First", estimate: 600)
        first.order = 1
        var second = makeTask(id: "second", title: "Second", estimate: nil)
        second.order = 0
        var plan = WeeklyPlan(id: "local", tasks: [first, second])

        try plan.deferTask("second", at: now, for: 30 * 60)
        let queue = plan.taskQueue(at: now.addingTimeInterval(60))

        XCTAssertEqual(queue.suggestedTask?.id, "first")
        XCTAssertEqual(queue.deferredTasks.map(\.id), ["second"])
        XCTAssertEqual(queue.nextDeferredReturn, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(queue.selectableTasks.map(\.id), ["first", "second"])
    }

    func testQueueReturnsDeferredTaskForKnownDeadlineRisk() throws {
        let task = makeTask(id: "urgent", title: "Urgent", estimate: 600)
        var plan = WeeklyPlan(id: "local", tasks: [task])
        try plan.deferTask("urgent", at: now, for: 30 * 60)

        let queue = plan.taskQueue(at: now.addingTimeInterval(60), deadlineAtRiskTaskIDs: ["urgent"])

        XCTAssertEqual(queue.suggestedTask?.id, "urgent")
        XCTAssertEqual(queue.deferredTasks, [])
        XCTAssertEqual(queue.returnedForDeadline, ["urgent"])
    }

    func testQueueReorderAndDirectSelectionPersistInPlanState() throws {
        let first = makeTask(id: "first", title: "First", estimate: 600)
        let second = makeTask(id: "second", title: "Second", estimate: 600)
        var plan = WeeklyPlan(id: "local", tasks: [first, second])

        try plan.reorderTasks(["second", "first"])
        try plan.deferTask("second", at: now)
        try plan.selectTask("second")

        XCTAssertEqual(plan.localState.taskOrder, ["second", "first"])
        XCTAssertEqual(plan.localState.selectedTaskID, "second")
        XCTAssertTrue(plan.localState.deferrals.isEmpty)
        XCTAssertEqual(plan.taskQueue(at: now).suggestedTask?.id, "second")
    }

    func testRemainingEstimateCanBecomeKnownOrExplicitlyUnknownWithoutLosingTask() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "task", title: "Grading", estimate: nil)])

        try plan.setRemainingEstimate("task", to: 90 * 60)
        XCTAssertEqual(task("task", in: plan).remainingEstimateSeconds, 90 * 60)
        XCTAssertFalse(plan.hasUnknownRemainingEffort)

        try plan.setRemainingEstimate("task", to: nil)
        XCTAssertNil(task("task", in: plan).remainingEstimateSeconds)
        XCTAssertTrue(plan.hasUnknownRemainingEffort)
        XCTAssertNil(task("task", in: plan).completedAt)
        XCTAssertNil(task("task", in: plan).abandonedAt)
    }

    func testQueueExcludesCompletedAndPrerequisiteBlockedWork() {
        var completed = makeTask(id: "done", title: "Done", estimate: 600)
        completed.completedAt = now
        var dependent = makeTask(id: "later", title: "Later", estimate: 600)
        dependent.prerequisiteTaskIDs = ["done"]
        var blocked = makeTask(id: "blocked", title: "Blocked", estimate: 600)
        blocked.prerequisiteTaskIDs = ["later"]
        let plan = WeeklyPlan(id: "local", tasks: [completed, dependent, blocked])

        XCTAssertEqual(plan.taskQueue(at: now).readyTasks.map(\.id), ["later"])
    }

    func testTodayPreviewWorksWithoutPlanningWindows() {
        let task = makeTask(id: "next", title: "Start anywhere", estimate: 1_800)
        let plan = WeeklyPlan(id: "local", tasks: [task])

        let preview = plan.todayPreview(at: now)

        XCTAssertFalse(preview.hasPlanningWindow)
        XCTAssertEqual(preview.queue.suggestedTask?.id, "next")
        XCTAssertTrue(preview.forecast.conflicts.contains(.missingFutureAvailability))
        XCTAssertTrue(preview.suggestedTaskIDs.isEmpty)
    }

    func testTodayPreviewKeepsCommitmentsFixedAndForecastsSuggestions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let day = "2027-01-15"
        let start = Date(timeIntervalSince1970: 1_800_018_000)
        let task = makeTask(id: "draft", title: "Draft", estimate: 3_600)
        let commitment = FixedCommitment(id: "meeting", sourceID: nil, title: "Meeting", time: PlanTimeRange(start: start, end: start.addingTimeInterval(1_800)))
        let plan = WeeklyPlan(id: "plan", availability: [DailyAvailability(day: day, windows: [PlanTimeRange(start: start, end: start.addingTimeInterval(7_200))])], tasks: [task], fixedCommitments: [commitment])

        let preview = plan.todayPreview(at: date, calendar: calendar)

        XCTAssertTrue(preview.hasPlanningWindow)
        XCTAssertEqual(preview.availableFocusSeconds, 7_200)
        XCTAssertEqual(preview.fixedCommitments.map(\.id), ["meeting"])
        XCTAssertEqual(preview.suggestedTaskIDs, ["draft"])
    }

    func testReviewedCarryoverKeepsIdentityHierarchyAndEstimateHistory() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Imported parent", estimate: 3_600)])
        plan.tasks[0].sourceID = "source:parent"
        try plan.addChild(makeTask(id: "child", title: "Local child", estimate: 600),
                          to: "parent", accounting: .usesParentEstimate, recordedAt: now)

        try plan.carryTaskForward("child")
        let restored = try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan))

        XCTAssertEqual(restored.localState.carryoverTaskIDs, ["child"])
        XCTAssertEqual(task("child", in: restored).parentTaskID, "parent")
        XCTAssertNil(task("child", in: restored).sourceID)
        XCTAssertEqual(restored.localState.estimateAdjustments.single?.accounting, .usesParentEstimate)
        XCTAssertEqual(restored.taskQueue(at: now).readyTasks.map(\.id), ["parent"])

        var returned = restored
        try returned.bringCarryoverIntoQueue("child")
        XCTAssertTrue(returned.taskQueue(at: now).readyTasks.contains { $0.id == "child" })
    }

    func testDayEndReviewUsesSegmentsOnceButProvidesParentRollup() throws {
        var plan = WeeklyPlan(id: "local", tasks: [makeTask(id: "parent", title: "Parent", estimate: 3_600)])
        try plan.addChild(makeTask(id: "child", title: "Child", estimate: 600),
                          to: "parent", accounting: .usesParentEstimate, recordedAt: now)
        let interval = ScheduledInterval(kind: .focus, startDate: now, endDate: now.addingTimeInterval(600), isAnchored: false)
        plan.localState.workSegments = [try TaskWorkSegment(taskID: "child", runID: UUID(), focusInterval: interval,
                                                            start: now, end: now.addingTimeInterval(300))]

        let review = plan.dayEndReview(at: now)
        let parent = try XCTUnwrap(review.taskRows.first { $0.id == "parent" })
        let child = try XCTUnwrap(review.taskRows.first { $0.id == "child" })

        XCTAssertEqual(review.actualWorkSeconds, 300)
        XCTAssertEqual(parent.ownActualWorkSeconds, 0)
        XCTAssertEqual(parent.rolledUpActualWorkSeconds, 300)
        XCTAssertEqual(child.ownActualWorkSeconds, 300)
        XCTAssertEqual(review.remainingKnownEffortSeconds, 3_600)
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
