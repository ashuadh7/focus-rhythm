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
    private(set) var scheduledDate: Date?
    private(set) var scheduledTitle: String?
    private(set) var scheduledBody: String?

    func requestAuthorization() {
        authorizationRequested = true
    }

    func schedulePhaseTransition(at date: Date, title: String, body: String) {
        scheduledDate = date
        scheduledTitle = title
        scheduledBody = body
    }

    func cancelPendingPhaseTransition() {
        scheduledDate = nil
        scheduledTitle = nil
        scheduledBody = nil
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
}
