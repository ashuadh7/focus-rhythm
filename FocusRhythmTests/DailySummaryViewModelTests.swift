import XCTest
@testable import FocusRhythm

final class DailySummaryViewModelTests: XCTestCase {
    func testSummarizesCompletedSessionsAndWaterForToday() {
        let sessionStore = InMemoryFocusSessionStore()
        let waterLogStore = InMemoryWaterLogStore()
        let now = Date()
        sessionStore.addSession(startedAt: now.addingTimeInterval(-3000), endedAt: now, duration: 3000, completed: true)
        sessionStore.addSession(startedAt: now.addingTimeInterval(-600), endedAt: now, duration: 600, completed: true)
        waterLogStore.addLog(amountMl: 250, date: now)
        waterLogStore.addLog(amountMl: 500, date: now)

        let viewModel = DailySummaryViewModel(sessionStore: sessionStore, waterLogStore: waterLogStore, now: { now })

        XCTAssertEqual(viewModel.totalFocusTime, 3600)
        XCTAssertEqual(viewModel.cycleCount, 2)
        XCTAssertEqual(viewModel.totalWaterMl, 750)
    }

    func testPartialSessionsContributeToFocusButNotCompletedSessionCount() {
        let sessionStore = InMemoryFocusSessionStore()
        let now = Date()
        sessionStore.addSession(startedAt: now.addingTimeInterval(-600), endedAt: now, duration: 600, completed: false)

        let viewModel = DailySummaryViewModel(sessionStore: sessionStore, waterLogStore: InMemoryWaterLogStore(), now: { now })

        XCTAssertEqual(viewModel.totalFocusTime, 600)
        XCTAssertEqual(viewModel.cycleCount, 0)
    }

    func testUsesFinalRunScheduleForPlannedTotalsAndCompletionState() {
        let sessionStore = InMemoryFocusSessionStore()
        let now = Date()
        let schedule = GeneratedDailySchedule(
            rhythmName: "Test",
            dayStart: now.addingTimeInterval(-3_600),
            dayEnd: now,
            intervals: [
                ScheduledInterval(kind: .focus, startDate: now.addingTimeInterval(-3_600), endDate: now.addingTimeInterval(-1_800), isAnchored: false),
                ScheduledInterval(kind: .focus, startDate: now.addingTimeInterval(-1_800), endDate: now, isAnchored: false)
            ]
        )
        let historyStore = InMemoryRunHistoryStore()
        historyStore.record(CompletedRhythmRun(startedAt: now.addingTimeInterval(-3_600), schedule: schedule, outcome: .endedEarly))
        sessionStore.addSession(startedAt: now.addingTimeInterval(-3_600), endedAt: now.addingTimeInterval(-1_800), duration: 1_800, completed: true)
        sessionStore.addSession(startedAt: now.addingTimeInterval(-1_800), endedAt: now.addingTimeInterval(-1_200), duration: 600, completed: false)

        let viewModel = DailySummaryViewModel(
            sessionStore: sessionStore,
            waterLogStore: InMemoryWaterLogStore(),
            runHistoryStore: historyStore,
            now: { now }
        )

        XCTAssertEqual(viewModel.plannedFocusTime, 3_600)
        XCTAssertEqual(viewModel.plannedCycleCount, 2)
        XCTAssertEqual(viewModel.totalFocusTime, 2_400)
        XCTAssertEqual(viewModel.cycleCount, 1)
        XCTAssertEqual(viewModel.runOutcome, .endedEarly)
    }

    func testDuplicateRestoredSessionIsCountedOnce() {
        let sessionStore = InMemoryFocusSessionStore()
        let now = Date()
        for _ in 0..<2 {
            sessionStore.addSession(startedAt: now.addingTimeInterval(-600), endedAt: now, duration: 600, completed: true)
        }

        let viewModel = DailySummaryViewModel(sessionStore: sessionStore, waterLogStore: InMemoryWaterLogStore(), now: { now })

        XCTAssertEqual(viewModel.totalFocusTime, 600)
        XCTAssertEqual(viewModel.cycleCount, 1)
    }

    func testActivityDetailIncludesFocusAndRunAdjustments() {
        let now = Date()
        let schedule = GeneratedDailySchedule(
            rhythmName: "Test",
            dayStart: now.addingTimeInterval(-1_200),
            dayEnd: now,
            intervals: [ScheduledInterval(kind: .focus, startDate: now.addingTimeInterval(-1_200), endDate: now, isAnchored: false, label: "Write brief")]
        )
        let sessions = InMemoryFocusSessionStore()
        sessions.addSession(startedAt: now.addingTimeInterval(-1_200), endedAt: now.addingTimeInterval(-600), duration: 600, completed: false)
        let history = InMemoryRunHistoryStore()
        history.record(CompletedRhythmRun(
            startedAt: now.addingTimeInterval(-1_200),
            schedule: schedule,
            outcome: .endedEarly,
            adjustments: [RunAdjustment(kind: .midWorkBreak, date: now.addingTimeInterval(-600), duration: 120, label: "Write brief")]
        ))

        let viewModel = DailySummaryViewModel(sessionStore: sessions, waterLogStore: InMemoryWaterLogStore(), runHistoryStore: history, now: { now })

        XCTAssertEqual(viewModel.activities, [DailyActivitySummary(id: schedule.intervals[0].id, title: "Write brief", plannedDuration: 1_200, actualDuration: 600, completed: false)])
        XCTAssertEqual(viewModel.adjustments.first?.kind, .midWorkBreak)
    }

    func testGroupsMultipleRunsIntoOneDayWithoutConflatingTheirDetails() {
        let now = Date()
        let morningStart = now.addingTimeInterval(-4 * 3_600)
        let eveningStart = now.addingTimeInterval(-60 * 60)
        let morningSchedule = GeneratedDailySchedule(
            rhythmName: "Morning",
            dayStart: morningStart,
            dayEnd: morningStart.addingTimeInterval(30 * 60),
            intervals: [ScheduledInterval(kind: .focus, startDate: morningStart, endDate: morningStart.addingTimeInterval(30 * 60), isAnchored: false, label: "Research")]
        )
        let eveningSchedule = GeneratedDailySchedule(
            rhythmName: "Evening",
            dayStart: eveningStart,
            dayEnd: eveningStart.addingTimeInterval(20 * 60),
            intervals: [ScheduledInterval(kind: .focus, startDate: eveningStart, endDate: eveningStart.addingTimeInterval(20 * 60), isAnchored: false, label: "Writing")]
        )
        let sessions = InMemoryFocusSessionStore()
        sessions.addSession(startedAt: morningStart, endedAt: morningStart.addingTimeInterval(15 * 60), duration: 15 * 60, completed: false)
        sessions.addSession(startedAt: eveningStart, endedAt: eveningStart.addingTimeInterval(20 * 60), duration: 20 * 60, completed: true)
        let history = InMemoryRunHistoryStore()
        history.record(CompletedRhythmRun(startedAt: morningStart, schedule: morningSchedule, outcome: .endedEarly))
        history.record(CompletedRhythmRun(startedAt: eveningStart, schedule: eveningSchedule, outcome: .completedAsPlanned))

        let viewModel = DailySummaryViewModel(sessionStore: sessions, waterLogStore: InMemoryWaterLogStore(), runHistoryStore: history, now: { now })

        XCTAssertEqual(viewModel.plannedFocusTime, 50 * 60)
        XCTAssertEqual(viewModel.totalFocusTime, 35 * 60)
        XCTAssertEqual(viewModel.runSummaries.count, 2)
        XCTAssertEqual(viewModel.runSummaries[0].activities.first?.title, "Research")
        XCTAssertEqual(viewModel.runSummaries[0].activities.first?.actualDuration, 15 * 60)
        XCTAssertEqual(viewModel.runSummaries[1].activities.first?.title, "Writing")
        XCTAssertEqual(viewModel.runSummaries[1].activities.first?.actualDuration, 20 * 60)
    }

    func testEmptyDayProducesZeroedSummary() {
        let viewModel = DailySummaryViewModel(
            sessionStore: InMemoryFocusSessionStore(),
            waterLogStore: InMemoryWaterLogStore(),
            now: Date.init
        )

        XCTAssertEqual(viewModel.totalFocusTime, 0)
        XCTAssertEqual(viewModel.cycleCount, 0)
        XCTAssertEqual(viewModel.totalWaterMl, 0)
    }
}
