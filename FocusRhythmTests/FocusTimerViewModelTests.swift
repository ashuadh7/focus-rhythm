import XCTest
@testable import FocusRhythm

final class InMemoryTimerSettingsStore: TimerSettingsStoring {
    private var workDuration: TimeInterval?
    private var breakDuration: TimeInterval?

    func loadWorkDuration() -> TimeInterval? { workDuration }
    func loadBreakDuration() -> TimeInterval? { breakDuration }

    func save(workDuration: TimeInterval, breakDuration: TimeInterval) {
        self.workDuration = workDuration
        self.breakDuration = breakDuration
    }
}

final class InMemoryNotificationScheduler: NotificationScheduling {
    private(set) var authorizationRequested = false
    private(set) var notifications: [TransitionNotification] = []

    var scheduledDate: Date? { notifications.first?.date }
    var scheduledTitle: String? { notifications.first?.title }
    var scheduledBody: String? { notifications.first?.body }

    func requestAuthorization() {
        authorizationRequested = true
    }

    func reconcileTransitionNotifications(_ notifications: [TransitionNotification]) {
        self.notifications = notifications
    }

    func cancelTransitionNotifications() {
        notifications = []
    }
}

final class FocusTimerViewModelTests: XCTestCase {
    func testDefaultDurationsMatchMVPDefaults() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())

        XCTAssertEqual(viewModel.workDuration, 50 * 60)
        XCTAssertEqual(viewModel.breakDuration, 10 * 60)
        XCTAssertEqual(viewModel.remainingTimeText, "50:00")
    }

    func testStartingFromIdleBeginsWorkBlock() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())

        viewModel.start()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
    }

    func testTickCountsDownDuringWorkPhase() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()

        viewModel.tick(90)

        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration - 90)
        XCTAssertEqual(viewModel.remainingTimeText, "48:30")
    }

    func testTickDoesNothingWhileIdle() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())

        viewModel.tick(30)

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
    }

    func testWorkPhaseAutomaticallyAdvancesToBreakWhenComplete() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()

        viewModel.tick(viewModel.workDuration)

        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(viewModel.remainingTime, viewModel.breakDuration)
    }

    func testBreakPhaseAutomaticallyAdvancesToNextWorkBlockWhenComplete() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(viewModel.workDuration)

        viewModel.tick(viewModel.breakDuration)

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
    }

    func testFullCycleRepeatsWithoutManualRestart() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()

        viewModel.tick(viewModel.workDuration)
        XCTAssertEqual(viewModel.phase, .break)

        viewModel.tick(viewModel.breakDuration)
        XCTAssertEqual(viewModel.phase, .work)

        viewModel.tick(viewModel.workDuration)
        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(viewModel.remainingTime, viewModel.breakDuration)
    }

    func testUpdatingDurationsPersistsAndAppliesWhileIdle() {
        let store = InMemoryTimerSettingsStore()
        let viewModel = FocusTimerViewModel(settingsStore: store)

        viewModel.updateDurations(workDuration: 25 * 60, breakDuration: 5 * 60)

        XCTAssertEqual(viewModel.workDuration, 25 * 60)
        XCTAssertEqual(viewModel.breakDuration, 5 * 60)
        XCTAssertEqual(viewModel.remainingTimeText, "25:00")
        XCTAssertEqual(store.loadWorkDuration(), 25 * 60)
        XCTAssertEqual(store.loadBreakDuration(), 5 * 60)
    }

    func testPersistedSettingsAreLoadedOnInit() {
        let store = InMemoryTimerSettingsStore()
        store.save(workDuration: 20 * 60, breakDuration: 3 * 60)

        let viewModel = FocusTimerViewModel(settingsStore: store)

        XCTAssertEqual(viewModel.workDuration, 20 * 60)
        XCTAssertEqual(viewModel.breakDuration, 3 * 60)
    }

    func testCompletingAWorkBlockRecordsACompletedSession() {
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: sessionStore)
        viewModel.start()

        viewModel.tick(viewModel.workDuration)

        XCTAssertEqual(sessionStore.allSessions.count, 1)
        XCTAssertEqual(sessionStore.allSessions.first?.duration, viewModel.workDuration)
        XCTAssertEqual(sessionStore.allSessions.first?.completed, true)
    }

    func testFullCycleRecordsOneSessionPerCompletedWorkBlock() {
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: sessionStore)
        viewModel.start()

        viewModel.tick(viewModel.workDuration)
        viewModel.tick(viewModel.breakDuration)
        viewModel.tick(viewModel.workDuration)

        XCTAssertEqual(sessionStore.allSessions.count, 2)
    }

    // MARK: - Add time

    func testAddTimeBecomesAvailableAt20PercentRemaining() {
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()

        viewModel.tick(50 * 60 - 10 * 60 - 1)
        XCTAssertFalse(viewModel.isAddTimeAvailable, "should not be available just above the 20% threshold")

        viewModel.tick(1)
        XCTAssertTrue(viewModel.isAddTimeAvailable)
        XCTAssertTrue(viewModel.isLowTimeWarningVisible)
    }

    func testAddTimeStacksBonusOnTopOfRemainingTime() {
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(50 * 60 - 9 * 60) // 9:00 remaining

        viewModel.addTime()

        XCTAssertEqual(viewModel.remainingTime, 19 * 60, "9:00 left + 10:00 bonus (20% of 50 min)")
        XCTAssertFalse(viewModel.isAddTimeAvailable, "one use per phase")
    }

    func testAddTimeCanOnlyBeUsedOncePerPhase() {
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(50 * 60 - 9 * 60)
        viewModel.addTime()
        let afterFirstAdd = viewModel.remainingTime

        viewModel.addTime()

        XCTAssertEqual(viewModel.remainingTime, afterFirstAdd, "second call should be a no-op")
    }

    func testBonusLowTimeWarningFiresAt20PercentOfBonusRemaining() {
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(50 * 60 - 9 * 60)
        viewModel.addTime() // remainingTime now 19:00, bonus 10:00

        viewModel.tick(19 * 60 - 2 * 60 - 1)
        XCTAssertFalse(viewModel.isBonusLowTimeWarningVisible)

        viewModel.tick(1)
        XCTAssertTrue(viewModel.isBonusLowTimeWarningVisible)
    }

    func testAddTimeAvailabilityResetsOnNewPhase() {
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(50 * 60 - 9 * 60)
        viewModel.addTime()
        viewModel.tick(19 * 60) // finishes work, moves to break

        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertFalse(viewModel.isAddTimeAvailable)

        viewModel.tick(10 * 60 - 10 * 60 * 0.2)
        XCTAssertTrue(viewModel.isAddTimeAvailable, "add-time should be usable again in the new phase")
    }

    // MARK: - Long-press interrupt (work -> break)

    func testCompletingHoldDuringWorkOpensBreakSelection() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()

        viewModel.completeHoldToInterrupt()

        XCTAssertTrue(viewModel.isSelectingBreakDuration)
        XCTAssertEqual(viewModel.phase, .work, "phase does not change until the break is confirmed")
    }

    func testTickFreezesWhileSelectingBreakDuration() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(60)
        viewModel.completeHoldToInterrupt()
        let remainingAtInterrupt = viewModel.remainingTime

        viewModel.tick(60)

        XCTAssertEqual(viewModel.remainingTime, remainingAtInterrupt)
    }

    func testCancelingBreakSelectionResumesWork() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.completeHoldToInterrupt()

        viewModel.cancelBreakSelection()

        XCTAssertFalse(viewModel.isSelectingBreakDuration)
        XCTAssertEqual(viewModel.phase, .work)

        viewModel.tick(60)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration - 60, "countdown resumes after cancel")
    }

    func testConfirmingBreakCommitsToChosenDurationAndDoesNotRecordASession() {
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: sessionStore)
        viewModel.start()
        viewModel.tick(20 * 60) // 30:00 remaining
        viewModel.completeHoldToInterrupt()

        viewModel.confirmBreak(duration: 5 * 60)

        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(viewModel.remainingTime, 5 * 60)
        XCTAssertFalse(viewModel.isSelectingBreakDuration)
        XCTAssertTrue(sessionStore.allSessions.isEmpty, "a mid-work break pauses the session rather than abandoning it")
    }

    func testMidWorkBreakDurationIsCappedRegardlessOfRequestedLength() {
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.completeHoldToInterrupt()

        viewModel.confirmBreak(duration: 20 * 60)

        XCTAssertEqual(viewModel.remainingTime, FocusTimerViewModel.midWorkBreakCap)
    }

    func testWorkResumesFromRemainingTimeAfterMidWorkBreakCompletes() {
        // 50 min work, 13 min elapsed -> 37:00 remaining when the break starts.
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(13 * 60)
        viewModel.completeHoldToInterrupt()
        viewModel.confirmBreak(duration: 5 * 60)

        viewModel.tick(5 * 60) // break completes naturally

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, 37 * 60, "resumes from where work left off, not a fresh block")
    }

    func testWorkResumesFromRemainingTimeWhenMidWorkBreakIsSkipped() {
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(13 * 60)
        viewModel.completeHoldToInterrupt()
        viewModel.confirmBreak(duration: 5 * 60)

        viewModel.completeHoldToInterrupt() // skip the mid-work break early

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, 37 * 60)
    }

    func testCompletingResumedWorkBlockRecordsOneCompletedSessionForTheFullDuration() {
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: sessionStore)
        viewModel.start()
        viewModel.tick(13 * 60)
        viewModel.completeHoldToInterrupt()
        viewModel.confirmBreak(duration: 5 * 60)
        viewModel.tick(5 * 60)

        viewModel.tick(37 * 60)

        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(sessionStore.allSessions.count, 1)
        XCTAssertEqual(sessionStore.allSessions.first?.completed, true)
        XCTAssertEqual(sessionStore.allSessions.first?.duration, 50 * 60)
    }

    // MARK: - Long-press interrupt (break -> work)

    func testCompletingHoldDuringBreakSkipsDirectlyToWork() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(viewModel.workDuration)
        XCTAssertEqual(viewModel.phase, .break)

        viewModel.completeHoldToInterrupt()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
        XCTAssertFalse(viewModel.isSelectingBreakDuration, "no picker when skipping a break")
    }

    func testSkippingBreakDoesNotAddASession() {
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: sessionStore)
        viewModel.start()
        viewModel.tick(viewModel.workDuration)
        let countAfterFirstWorkBlock = sessionStore.allSessions.count

        viewModel.completeHoldToInterrupt()

        XCTAssertEqual(sessionStore.allSessions.count, countAfterFirstWorkBlock)
    }

    // MARK: - End cycle

    private static let longEnoughReasoning = Array(repeating: "reason", count: 20).joined(separator: " ")
    private static let tooShortReasoning = "not enough words here"

    func testConfirmEndCycleFailsWithFewerThanMinimumWords() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.requestEndCycle()

        let succeeded = viewModel.confirmEndCycle(reasoning: Self.tooShortReasoning)

        XCTAssertFalse(succeeded)
        XCTAssertTrue(viewModel.isEndingCycle)
        XCTAssertEqual(viewModel.phase, .work)
    }

    func testConfirmEndCycleReturnsToIdleWithEnoughReasoning() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())
        viewModel.start()
        viewModel.tick(60)
        viewModel.requestEndCycle()

        let succeeded = viewModel.confirmEndCycle(reasoning: Self.longEnoughReasoning)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertFalse(viewModel.isEndingCycle)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
    }

    func testEndingCycleDuringWorkRecordsIncompleteSessionForElapsedTime() {
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: sessionStore)
        viewModel.start()
        viewModel.tick(13 * 60)
        viewModel.requestEndCycle()

        viewModel.confirmEndCycle(reasoning: Self.longEnoughReasoning)

        XCTAssertEqual(sessionStore.allSessions.count, 1)
        XCTAssertEqual(sessionStore.allSessions.first?.completed, false)
        XCTAssertEqual(sessionStore.allSessions.first?.duration, 13 * 60)
    }

    func testEndingCycleDuringMidWorkBreakRecordsElapsedWorkTimeNotBreakTime() {
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(workDuration: 50 * 60, breakDuration: 10 * 60, settingsStore: InMemoryTimerSettingsStore(), sessionStore: sessionStore)
        viewModel.start()
        viewModel.tick(13 * 60)
        viewModel.completeHoldToInterrupt()
        viewModel.confirmBreak(duration: 5 * 60)
        viewModel.requestEndCycle()

        viewModel.confirmEndCycle(reasoning: Self.longEnoughReasoning)

        XCTAssertEqual(sessionStore.allSessions.count, 1)
        XCTAssertEqual(sessionStore.allSessions.first?.completed, false)
        XCTAssertEqual(sessionStore.allSessions.first?.duration, 13 * 60)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testRequestEndCycleIsNoOpWhileIdle() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore(), sessionStore: InMemoryFocusSessionStore())

        viewModel.requestEndCycle()

        XCTAssertFalse(viewModel.isEndingCycle)
    }

    // MARK: - Backgrounding / wall-clock recompute

    func testStartingWorkSchedulesANotificationForThePhaseEndTime() {
        let scheduler = InMemoryNotificationScheduler()
        let currentDate = Date(timeIntervalSince1970: 0)
        let viewModel = FocusTimerViewModel(
            workDuration: 50 * 60,
            breakDuration: 10 * 60,
            settingsStore: InMemoryTimerSettingsStore(),
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: scheduler,
            now: { currentDate }
        )

        viewModel.start()

        XCTAssertEqual(viewModel.phaseEndTime, currentDate.addingTimeInterval(50 * 60))
        XCTAssertEqual(scheduler.scheduledDate, currentDate.addingTimeInterval(50 * 60))
        XCTAssertNotNil(scheduler.scheduledTitle)
    }

    func testRefreshForForegroundRecomputesRemainingTimeWithoutCrossingPhaseBoundary() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let viewModel = FocusTimerViewModel(
            workDuration: 50 * 60,
            breakDuration: 10 * 60,
            settingsStore: InMemoryTimerSettingsStore(),
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            now: { currentDate }
        )
        viewModel.start()

        currentDate = currentDate.addingTimeInterval(20 * 60) // backgrounded for 20 minutes
        viewModel.refreshForForeground()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, 30 * 60)
    }

    func testRefreshForForegroundCatchesUpThroughACompletedPhase() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(
            workDuration: 50 * 60,
            breakDuration: 10 * 60,
            settingsStore: InMemoryTimerSettingsStore(),
            sessionStore: sessionStore,
            notificationScheduler: InMemoryNotificationScheduler(),
            now: { currentDate }
        )
        viewModel.start()

        currentDate = currentDate.addingTimeInterval(55 * 60) // work finishes, 5 min into break
        viewModel.refreshForForeground()

        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(viewModel.remainingTime, 5 * 60)
        XCTAssertEqual(sessionStore.allSessions.count, 1, "the completed work block should be recorded")
    }

    func testRefreshForForegroundCatchesUpThroughMultiplePhases() {
        var currentDate = Date(timeIntervalSince1970: 0)
        let viewModel = FocusTimerViewModel(
            workDuration: 50 * 60,
            breakDuration: 10 * 60,
            settingsStore: InMemoryTimerSettingsStore(),
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            now: { currentDate }
        )
        viewModel.start()

        currentDate = currentDate.addingTimeInterval(65 * 60) // work + break both finish, 5 min into next work
        viewModel.refreshForForeground()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, 45 * 60)
    }

    func testCompletingHoldToInterruptCancelsThePendingNotification() {
        let scheduler = InMemoryNotificationScheduler()
        let viewModel = FocusTimerViewModel(
            settingsStore: InMemoryTimerSettingsStore(),
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: scheduler
        )
        viewModel.start()
        XCTAssertNotNil(scheduler.scheduledDate)

        viewModel.completeHoldToInterrupt()

        XCTAssertNil(scheduler.scheduledDate)
    }

    // MARK: - Finite schedule runtime

    func testScheduleRunStartsInCurrentIntervalAndExposesNextTransitionAndDayEnd() {
        let start = Date(timeIntervalSince1970: 10_000)
        let run = makeRun(start: start)
        let viewModel = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            now: { start.addingTimeInterval(60) }
        )

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.currentBlockName, "Test task")
        XCTAssertEqual(viewModel.remainingTime, 9 * 60)
        XCTAssertEqual(viewModel.nextTransition?.title, "Short break")
        XCTAssertEqual(viewModel.nextTransition?.date, start.addingTimeInterval(10 * 60))
        XCTAssertEqual(viewModel.dayEnd, start.addingTimeInterval(35 * 60))
    }

    func testStartingScheduleRunSchedulesEveryFutureTransitionAndDayEnd() {
        let start = Date(timeIntervalSince1970: 10_500)
        let scheduler = InMemoryNotificationScheduler()

        _ = FocusTimerViewModel(
            run: makeRun(start: start),
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: scheduler,
            now: { start }
        )

        XCTAssertEqual(
            scheduler.notifications.map(\.date),
            [10, 15, 20, 25, 35].map { start.addingTimeInterval(TimeInterval($0 * 60)) }
        )
        XCTAssertEqual(scheduler.notifications.last?.title, "Day complete")
        XCTAssertEqual(Set(scheduler.notifications.map(\.identifier)).count, scheduler.notifications.count)
    }

    func testRestoringUnchangedScheduleUsesTheSameNotificationIdentifiers() {
        let start = Date(timeIntervalSince1970: 11_000)
        let run = makeRun(start: start)
        let firstScheduler = InMemoryNotificationScheduler()
        let restoredScheduler = InMemoryNotificationScheduler()

        _ = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: firstScheduler,
            now: { start }
        )
        _ = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: restoredScheduler,
            now: { start }
        )

        XCTAssertEqual(
            firstScheduler.notifications.map(\.identifier),
            restoredScheduler.notifications.map(\.identifier)
        )
    }

    func testScheduleRevisionReplacesNotificationIdentifierSet() {
        let start = Date(timeIntervalSince1970: 11_500)
        let activeRunStore = InMemoryActiveRunStore()
        let run = makeRun(start: start)
        activeRunStore.run = run
        let scheduler = InMemoryNotificationScheduler()
        let viewModel = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: scheduler,
            activeRunStore: activeRunStore,
            now: { start }
        )
        let originalIdentifiers = Set(scheduler.notifications.map(\.identifier))

        viewModel.completeHoldToInterrupt()
        viewModel.confirmBreak(duration: 3 * 60)

        let revisedIdentifiers = Set(scheduler.notifications.map(\.identifier))
        XCTAssertTrue(revisedIdentifiers.allSatisfy { $0.contains(".r2.") })
        XCTAssertTrue(originalIdentifiers.isDisjoint(with: revisedIdentifiers))
        XCTAssertTrue(scheduler.notifications.contains { $0.identifier.hasSuffix("quick-break-end") })
        XCTAssertEqual(activeRunStore.run?.schedule.intervals.first?.label, "Test task")
    }

    func testManualTestRunUsesSecondScaleBreakPicker() {
        let start = Date(timeIntervalSince1970: 11_750)
        let schedule = GeneratedDailySchedule(
            rhythmName: "Manual test",
            dayStart: start,
            dayEnd: start.addingTimeInterval(50),
            intervals: [
                ScheduledInterval(kind: .focus, startDate: start, endDate: start.addingTimeInterval(20), isAnchored: false, label: "Task"),
                ScheduledInterval(kind: .shortBreak, startDate: start.addingTimeInterval(20), endDate: start.addingTimeInterval(30), isAnchored: false),
                ScheduledInterval(kind: .focus, startDate: start.addingTimeInterval(30), endDate: start.addingTimeInterval(50), isAnchored: false, label: "Next")
            ]
        )
        let rhythm = DailyRhythm(
            name: "Manual test",
            dayStart: TimeOfDay(hour: 9, minute: 0),
            dayEnd: TimeOfDay(hour: 9, minute: 1),
            workDuration: 20,
            shortBreakDuration: 10,
            workSections: [],
            longBreaks: []
        )
        let run = ActiveRhythmRun(variationID: nil, rhythm: rhythm, schedule: schedule, startedAt: start)
        let viewModel = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            now: { start }
        )

        XCTAssertTrue(viewModel.usesSecondScaleBreakPicker)
        XCTAssertEqual(viewModel.midWorkBreakPickerDefault, 10)
    }

    func testScheduleAdvancesThroughShortAndLongBreaksWithoutRestart() {
        let start = Date(timeIntervalSince1970: 20_000)
        let viewModel = FocusTimerViewModel(
            run: makeRun(start: start),
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            now: { start }
        )

        viewModel.tick(11 * 60)
        XCTAssertEqual(viewModel.phase, .shortBreak)

        viewModel.tick(10 * 60)
        XCTAssertEqual(viewModel.phase, .longBreak(name: "Lunch"))

        viewModel.tick(5 * 60)
        XCTAssertEqual(viewModel.phase, .work)
    }

    func testForegroundCatchUpRecordsPassedFocusIntervalsOnce() {
        let start = Date(timeIntervalSince1970: 30_000)
        var currentDate = start
        let sessionStore = InMemoryFocusSessionStore()
        let viewModel = FocusTimerViewModel(
            run: makeRun(start: start),
            sessionStore: sessionStore,
            notificationScheduler: InMemoryNotificationScheduler(),
            now: { currentDate }
        )

        currentDate = start.addingTimeInterval(34 * 60)
        viewModel.refreshForForeground()
        viewModel.refreshForForeground()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, 60)
        XCTAssertEqual(sessionStore.allSessions.count, 2)
        XCTAssertTrue(sessionStore.allSessions.allSatisfy(\.completed))
    }

    func testRelaunchCatchUpPersistsRecordedIntervalsAndAvoidsDuplicateSessions() {
        let start = Date(timeIntervalSince1970: 35_000)
        let activeRunStore = InMemoryActiveRunStore()
        activeRunStore.run = makeRun(start: start)
        let sessionStore = InMemoryFocusSessionStore()

        _ = FocusTimerViewModel(
            run: activeRunStore.run!,
            sessionStore: sessionStore,
            notificationScheduler: InMemoryNotificationScheduler(),
            activeRunStore: activeRunStore,
            now: { start.addingTimeInterval(26 * 60) }
        )
        _ = FocusTimerViewModel(
            run: activeRunStore.run!,
            sessionStore: sessionStore,
            notificationScheduler: InMemoryNotificationScheduler(),
            activeRunStore: activeRunStore,
            now: { start.addingTimeInterval(34 * 60) }
        )

        XCTAssertEqual(sessionStore.allSessions.count, 2)
        XCTAssertEqual(activeRunStore.run?.recordedIntervalIDs.count, 2)
    }

    func testScheduledLongPressBreakReturnsToInterruptedWork() {
        let start = Date(timeIntervalSince1970: 37_000)
        let activeRunStore = InMemoryActiveRunStore()
        let run = makeRun(start: start)
        activeRunStore.run = run
        let viewModel = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            activeRunStore: activeRunStore,
            now: { start }
        )

        viewModel.completeHoldToInterrupt()
        XCTAssertTrue(viewModel.isSelectingBreakDuration)
        viewModel.confirmBreak(duration: 3 * 60)

        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(viewModel.remainingTime, 3 * 60)
        XCTAssertEqual(activeRunStore.run?.scheduleRevision, 2)

        viewModel.tick(3 * 60)

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, 10 * 60)
    }

    func testScheduledShortBreakCanBeSkippedWithHold() {
        let start = Date(timeIntervalSince1970: 38_000)
        var currentDate = start
        let activeRunStore = InMemoryActiveRunStore()
        let run = makeRun(start: start)
        activeRunStore.run = run
        let viewModel = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            activeRunStore: activeRunStore,
            now: { currentDate }
        )
        viewModel.tick(11 * 60)
        currentDate = start.addingTimeInterval(11 * 60)

        viewModel.completeHoldToInterrupt()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, 5 * 60)
        XCTAssertEqual(activeRunStore.run?.scheduleRevision, 2)
    }

    func testScheduleStopsAtFixedDayEnd() {
        let start = Date(timeIntervalSince1970: 40_000)
        let sessionStore = InMemoryFocusSessionStore()
        let scheduler = InMemoryNotificationScheduler()
        let viewModel = FocusTimerViewModel(
            run: makeRun(start: start),
            sessionStore: sessionStore,
            notificationScheduler: scheduler,
            now: { start }
        )

        viewModel.tick(40 * 60)

        XCTAssertEqual(viewModel.phase, .completedDay)
        XCTAssertEqual(viewModel.remainingTime, 0)
        XCTAssertNil(viewModel.nextTransition)
        XCTAssertEqual(sessionStore.allSessions.count, 3)
        XCTAssertTrue(scheduler.notifications.isEmpty)
    }

    func testScheduleCompletionIsPersisted() {
        let start = Date(timeIntervalSince1970: 45_000)
        let activeRunStore = InMemoryActiveRunStore()
        let run = makeRun(start: start)
        activeRunStore.run = run
        let viewModel = FocusTimerViewModel(
            run: run,
            sessionStore: InMemoryFocusSessionStore(),
            notificationScheduler: InMemoryNotificationScheduler(),
            activeRunStore: activeRunStore,
            now: { start }
        )

        viewModel.tick(40 * 60)

        XCTAssertEqual(activeRunStore.run?.status, .completed)
        XCTAssertEqual(activeRunStore.run?.recordedIntervalIDs.count, 3)
    }

    private func makeRun(start: Date) -> ActiveRhythmRun {
        let schedule = GeneratedDailySchedule(
            rhythmName: "Test",
            dayStart: start,
            dayEnd: start.addingTimeInterval(35 * 60),
            intervals: [
                ScheduledInterval(kind: .focus, startDate: start, endDate: start.addingTimeInterval(10 * 60), isAnchored: false, label: "Test task"),
                ScheduledInterval(kind: .shortBreak, startDate: start.addingTimeInterval(10 * 60), endDate: start.addingTimeInterval(15 * 60), isAnchored: false),
                ScheduledInterval(kind: .focus, startDate: start.addingTimeInterval(15 * 60), endDate: start.addingTimeInterval(20 * 60), isAnchored: false),
                ScheduledInterval(kind: .longBreak(name: "Lunch"), startDate: start.addingTimeInterval(20 * 60), endDate: start.addingTimeInterval(25 * 60), isAnchored: true),
                ScheduledInterval(kind: .focus, startDate: start.addingTimeInterval(25 * 60), endDate: start.addingTimeInterval(35 * 60), isAnchored: false)
            ]
        )
        let rhythm = DailyRhythm(
            name: "Test",
            dayStart: TimeOfDay(hour: 9, minute: 0),
            dayEnd: TimeOfDay(hour: 17, minute: 0),
            workDuration: 10 * 60,
            shortBreakDuration: 5 * 60,
            workSections: [],
            longBreaks: []
        )
        return ActiveRhythmRun(variationID: nil, rhythm: rhythm, schedule: schedule, startedAt: start)
    }
}
