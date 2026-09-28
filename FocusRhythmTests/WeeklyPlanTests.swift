import XCTest
@testable import FocusRhythm

final class WeeklyPlanTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "weekly-plan-v1", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func fixture() throws -> WeeklyPlan { try WeeklyPlanJSON.decode(fixtureData()) }

    func testCanonicalExampleRoundTripsAllPlanningAndLocalState() throws {
        let plan = try fixture()
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)
        // Local persistence is free to use standard Codable dates too.
        XCTAssertEqual(try JSONDecoder().decode(WeeklyPlan.self, from: JSONEncoder().encode(plan)), plan)
        XCTAssertEqual(plan.allocations.map(\.taskID), ["grading", "grading"])
        XCTAssertEqual(plan.tasks[0].categoryTags, ["professional growth"])
        XCTAssertEqual(plan.localState.taskOrder, ["overdue", "grading", "reading", "email"])
        XCTAssertEqual(plan.localState.deferrals[0].taskID, "overdue")
        XCTAssertEqual(plan.fixedCommitments[0].title, "Teaching meeting")
        XCTAssertLessThan(plan.tasks[2].deadline!, plan.localState.deferrals[0].deferredAt)
    }

    func testTaskTotalsIgnoreSplitAllocationsBreaksAndCompletedRemainingEstimate() throws {
        var plan = try fixture()
        XCTAssertEqual(plan.originalEffortSeconds, 15900)
        XCTAssertEqual(plan.remainingEffortSeconds, 10800)
        XCTAssertEqual(plan.actualWorkSeconds(for: "grading"), 40 * 60)
        XCTAssertEqual(plan.actualWorkSeconds(for: "email"), 10 * 60)
        XCTAssertEqual(plan.actualWorkSeconds(for: "overdue"), 0)
        // Suggestions may be stale or exceed capacity: they never add task effort.
        plan.allocations[0].plannedEffortSeconds = 100000
        plan.allocations[0].suggestedTime?.end.addTimeInterval(3600)
        try plan.validate()
        XCTAssertEqual(plan.originalEffortSeconds, 15900)
        XCTAssertEqual(plan.remainingEffortSeconds, 10800)
        XCTAssertEqual(plan.actualWorkSeconds(for: "grading"), 2400)
    }

    func testEstimateExhaustionAndRevisionDoNotCompleteTasks() throws {
        var plan = try fixture()
        XCTAssertTrue(plan.tasks[2].needsEstimateRevision)
        XCTAssertNil(plan.tasks[2].completedAt)
        XCTAssertFalse(plan.tasks[1].needsEstimateRevision)
        plan.tasks[0].remainingEstimateSeconds += 30 * 60
        XCTAssertEqual(plan.tasks[0].originalEstimateSeconds, 10800)
        XCTAssertEqual(plan.actualWorkSeconds(for: "grading"), 2400)
        XCTAssertEqual(plan.remainingEffortSeconds, 12600)
        XCTAssertNil(plan.tasks[0].completedAt)
        try plan.validate()
    }

    func testAbsentAvailabilityDiffersFromExplicitUnavailableDay() throws {
        var plan = try fixture()
        XCTAssertTrue(try XCTUnwrap(plan.availability)[1].windows.isEmpty)
        XCTAssertNil(plan.availability?.first { $0.day == "2026-09-30" })
        plan.availability = nil
        XCTAssertNil(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)).availability)
        plan.availability = []
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)).availability, [])
    }

    func testSourceOnlyImportDefaultsToEmptyLocalState() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
        json.removeValue(forKey: "localState")
        json.removeValue(forKey: "availability")
        let plan = try WeeklyPlanJSON.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(plan.localState, PlanLocalState())
        XCTAssertNil(plan.availability)
        XCTAssertEqual(plan.tasks.count, 4)
    }

    func testMemberwiseConstructionUsesCurrentVersion() throws {
        let plan = WeeklyPlan(id: "empty-week", sourceID: "local", timeZoneIdentifier: "UTC",
                              horizon: PlanHorizon(startDay: "2026-09-28", endDayExclusive: "2026-10-05"), tasks: [])
        XCTAssertEqual(plan.schemaVersion, 1)
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)
    }

    func testRejectsUnknownVersionBeforeParsingNewPayload() {
        XCTAssertThrowsError(try WeeklyPlanJSON.decode(Data(#"{"schemaVersion":2}"#.utf8))) { error in
            XCTAssertEqual((error as? PlanValidationError)?.path, "schemaVersion")
        }
    }

    func testRejectsInvalidIdentityReferencesOrderingAndRangesOnDecode() throws {
        let edits: [(String, (inout WeeklyPlan) -> Void)] = [
            ("id", { $0.id = " " }),
            ("sourceID", { $0.sourceID = "" }),
            ("timeZoneIdentifier", { $0.timeZoneIdentifier = "Mars/Olympus" }),
            ("horizon.startDay", { $0.horizon.startDay = "2026-02-30" }),
            ("horizon", { $0.horizon.endDayExclusive = "2026-09-28" }),
            ("tasks.id", { $0.tasks[1].id = "grading" }),
            ("tasks.sourceID", { $0.tasks[1].sourceID = $0.tasks[0].sourceID }),
            ("tasks[0].title", { $0.tasks[0].title = "\n" }),
            ("tasks[0].originalEstimateSeconds", { $0.tasks[0].originalEstimateSeconds = -1 }),
            ("tasks[0].remainingEstimateSeconds", { $0.tasks[0].remainingEstimateSeconds = -1 }),
            ("tasks[0].minimumChunkSeconds", { $0.tasks[0].minimumChunkSeconds = -1 }),
            ("tasks[0].order", { $0.tasks[0].order = -1 }),
            ("tasks[1].order", { $0.tasks[1].order = 0 }),
            ("tasks[0].prerequisiteTaskIDs", { $0.tasks[0].prerequisiteTaskIDs = ["missing"] }),
            ("tasks[0].prerequisiteTaskIDs", { $0.tasks[0].prerequisiteTaskIDs = ["email", "email"] }),
            ("allocations.id", { $0.allocations[1].id = $0.allocations[0].id }),
            ("allocations[0].taskID", { $0.allocations[0].taskID = "missing" }),
            ("allocations[0].preferredDay", { $0.allocations[0].preferredDay = "2026-9-28" }),
            ("allocations[0].suggestedTime", { let start = $0.allocations[0].suggestedTime!.start; $0.allocations[0].suggestedTime?.end = start }),
            ("allocations[0].suggestedTime", { $0.allocations[0].preferredDay = "2026-09-29" }),
            ("allocations[0].plannedEffortSeconds", { $0.allocations[0].plannedEffortSeconds = -10 }),
            ("fixedCommitments.id", { $0.fixedCommitments.append($0.fixedCommitments[0]) }),
            ("fixedCommitments[0].time", { $0.fixedCommitments[0].time.end = $0.fixedCommitments[0].time.start }),
            ("availability.day", { let entry = $0.availability![0]; $0.availability?.append(entry) }),
            ("availability[0].day", { $0.availability?[0].day = "2026-09-27" }),
            ("availability[0].windows", { let window = $0.availability![0].windows[0]; $0.availability?[0].windows.append(window) }),
            ("availability[0].windows[0]", { $0.availability?[0].windows[0].start.addTimeInterval(-86400) }),
            ("localState.taskOrder", { $0.localState.taskOrder = ["grading"] }),
            ("localState.taskOrder", { $0.localState.taskOrder = ["grading", "email", "overdue", "missing"] }),
            ("localState.taskOrder", { $0.localState.taskOrder = ["grading", "email", "overdue", "grading"] }),
            ("localState.deferrals.taskID", { $0.localState.deferrals.append($0.localState.deferrals[0]) }),
            ("localState.deferrals[0].taskID", { $0.localState.deferrals[0].taskID = "missing" }),
            ("localState.deferrals[0]", { $0.localState.deferrals[0].until = $0.localState.deferrals[0].deferredAt }),
            ("localState.workSegments.id", { $0.localState.workSegments.append($0.localState.workSegments[0]) }),
            ("localState.workSegments[0].taskID", { $0.localState.workSegments[0].taskID = "missing" }),
            ("localState.workSegments[0].time", { $0.localState.workSegments[0].time.end = $0.localState.workSegments[0].time.start }),
            ("localState.workSegments", { $0.localState.workSegments[1].time.start.addTimeInterval(-1) })
        ]
        for (path, edit) in edits {
            var plan = try fixture()
            edit(&plan)
            assertInvalid(plan, path: path)
        }
    }

    func testRejectsNonFiniteValuesBeforeExport() throws {
        var plan = try fixture()
        for value in [Double.infinity, -.infinity, .nan] {
            plan.tasks[0].remainingEstimateSeconds = value
            XCTAssertThrowsError(try WeeklyPlanJSON.encode(plan))
        }
        plan = try fixture()
        plan.tasks[0].deadline = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertThrowsError(try plan.validate())
    }

    func testRejectsSelfAndMultiTaskCyclesButAcceptsSharedPrerequisites() throws {
        var plan = try fixture()
        plan.tasks[0].prerequisiteTaskIDs = ["grading"]
        assertInvalid(plan, path: "tasks.prerequisiteTaskIDs")
        plan.tasks[0].prerequisiteTaskIDs = ["overdue"]
        plan.tasks[1].prerequisiteTaskIDs = ["grading"]
        assertInvalid(plan, path: "tasks.prerequisiteTaskIDs")
        plan.tasks[1].prerequisiteTaskIDs = []
        plan.tasks[3].prerequisiteTaskIDs = ["email", "overdue"]
        try plan.validate()
    }

    func testPastPreferencesOverdueTasksAndConflictingFixedEventsRemainReviewable() throws {
        var plan = try fixture()
        plan.allocations[1].preferredDay = "2025-01-01"
        var conflicting = plan.fixedCommitments[0]
        conflicting.id = "second-meeting"
        conflicting.sourceID = nil
        plan.fixedCommitments.append(conflicting)
        try plan.validate()
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)
    }

    func testDateValidationIncludesLeapDaysAndDaylightSavingBoundaries() throws {
        XCTAssertTrue(WeeklyPlan.isValidDay("2024-02-29"))
        for value in ["2026-02-29", "2026-04-31", "2026-13-01", "0000-01-01", "2026-01-00"] {
            XCTAssertFalse(WeeklyPlan.isValidDay(value), value)
        }
        var plan = try fixture()
        plan.horizon = PlanHorizon(startDay: "2026-11-01", endDayExclusive: "2026-11-02")
        let range = PlanTimeRange(start: date("2026-11-01T00:00:00-04:00"), end: date("2026-11-02T00:00:00-05:00"))
        plan.availability = [DailyAvailability(day: "2026-11-01", windows: [range])]
        XCTAssertEqual(range.duration, 25 * 3600)
        try plan.validate()
        plan.availability?[0].windows[0].end.addTimeInterval(1)
        assertInvalid(plan, path: "availability[0].windows[0]")
    }

    func testMalformedJSONReturnsFieldAndItemPaths() throws {
        let data = try fixtureData()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var tasks = try XCTUnwrap(json["tasks"] as? [[String: Any]])
        tasks[0].removeValue(forKey: "title")
        json["tasks"] = tasks
        XCTAssertThrowsError(try WeeklyPlanJSON.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual((error as? PlanValidationError)?.path, "tasks[0].title")
        }
        tasks[0]["title"] = 12
        json["tasks"] = tasks
        XCTAssertThrowsError(try WeeklyPlanJSON.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual((error as? PlanValidationError)?.path, "tasks[0].title")
        }
        let source = String(decoding: data, as: UTF8.self)
        for invalid in ["2026-02-30T17:00:00-04:00", "2026-10-02T25:00:00-04:00", "2026-10-02T17:00:00", "2026-10-02T17:00:00.1234Z"] {
            let changed = source.replacingOccurrences(of: "2026-10-02T17:00:00-04:00", with: invalid)
            XCTAssertThrowsError(try WeeklyPlanJSON.decode(Data(changed.utf8))) { error in
                XCTAssertEqual((error as? PlanValidationError)?.path, "tasks[0].deadline")
            }
        }
    }

    func testFractionalTimestampExportRetainsMilliseconds() throws {
        var plan = try fixture()
        plan.tasks[0].deadline = date("2026-10-02T17:00:00Z").addingTimeInterval(0.125)
        let decoded = try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan))
        XCTAssertEqual(decoded.tasks[0].deadline, plan.tasks[0].deadline)
    }

    func testTaskCanSpanIntervalsAndIntervalCanContainSeveralTasks() throws {
        var plan = try fixture()
        let first = plan.localState.workSegments[0]
        let interval = ScheduledInterval(id: first.focusIntervalID, kind: .focus,
            startDate: first.time.start, endDate: first.time.start.addingTimeInterval(3000), isAnchored: false)
        let next = ScheduledInterval(kind: .focus, startDate: interval.endDate.addingTimeInterval(600),
            endDate: interval.endDate.addingTimeInterval(3600), isAnchored: false)
        let segment = try TaskWorkSegment(taskID: "grading", runID: first.runID, focusInterval: next,
            start: next.startDate, end: next.startDate.addingTimeInterval(1200))
        plan.localState.workSegments.append(segment)
        let schedule = GeneratedDailySchedule(rhythmName: "Test", dayStart: interval.startDate,
            dayEnd: next.endDate, intervals: [interval, next])
        try plan.validateWorkSegments(in: schedule, runID: first.runID)
        XCTAssertEqual(plan.actualWorkSeconds(for: "grading"), 3600)
        XCTAssertEqual(plan.actualWorkSeconds(for: "email"), 600)
        XCTAssertEqual(try WeeklyPlanJSON.decode(WeeklyPlanJSON.encode(plan)), plan)
        // Unattributed focus is retained without inventing task progress.
        plan.localState.workSegments[3].taskID = nil
        try plan.validate()
        XCTAssertEqual(plan.actualWorkSeconds(for: "grading"), 2400)
    }

    func testActualWorkRejectsBreaksOutsideBoundsAndForgedIntervalReferences() throws {
        var plan = try fixture()
        let first = plan.localState.workSegments[0]
        let rest = ScheduledInterval(id: first.focusIntervalID, kind: .shortBreak,
            startDate: first.time.start, endDate: first.time.start.addingTimeInterval(3000), isAnchored: false)
        XCTAssertThrowsError(try TaskWorkSegment(taskID: "grading", runID: first.runID,
            focusInterval: rest, start: rest.startDate, end: rest.endDate))
        let focus = ScheduledInterval(id: first.focusIntervalID, kind: .focus,
            startDate: rest.startDate, endDate: rest.endDate, isAnchored: false)
        XCTAssertThrowsError(try TaskWorkSegment(taskID: "grading", runID: first.runID,
            focusInterval: focus, start: focus.startDate, end: focus.endDate.addingTimeInterval(1)))
        for intervals in [[], [rest]] {
            let schedule = GeneratedDailySchedule(rhythmName: "Invalid", dayStart: rest.startDate,
                dayEnd: rest.endDate, intervals: intervals)
            XCTAssertThrowsError(try plan.validateWorkSegments(in: schedule, runID: first.runID))
        }
        let reduced = ScheduledInterval(id: first.focusIntervalID, kind: .focus, startDate: rest.startDate,
            endDate: rest.endDate, isAnchored: false, excludedDuration: 600)
        let schedule = GeneratedDailySchedule(rhythmName: "Interrupted", dayStart: rest.startDate,
            dayEnd: rest.endDate, intervals: [reduced])
        XCTAssertThrowsError(try plan.validateWorkSegments(in: schedule, runID: first.runID))
        plan.localState.workSegments.removeLast()
        try plan.validateWorkSegments(in: schedule, runID: first.runID)
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func assertInvalid(_ plan: WeeklyPlan, path: String, file: StaticString = #filePath, line: UInt = #line) {
        let actions: [() throws -> Void] = [
            { try plan.validate() },
            { _ = try WeeklyPlanJSON.encode(plan) },
            { _ = try JSONDecoder().decode(WeeklyPlan.self, from: JSONEncoder().encode(plan)) }
        ]
        for action in actions {
            XCTAssertThrowsError(try action(), path, file: file, line: line) { error in
                let validation = error as? PlanValidationError
                XCTAssertTrue(validation?.path.hasPrefix(path) == true, "\(path): \(error)", file: file, line: line)
                XCTAssertFalse(validation?.message.isEmpty ?? true, file: file, line: line)
            }
        }
    }
}
