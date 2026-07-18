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

final class FocusTimerViewModelTests: XCTestCase {
    func testDefaultDurationsMatchMVPDefaults() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())

        XCTAssertEqual(viewModel.workDuration, 50 * 60)
        XCTAssertEqual(viewModel.breakDuration, 10 * 60)
        XCTAssertEqual(viewModel.remainingTimeText, "50:00")
    }

    func testStartingFromIdleBeginsWorkBlock() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())

        viewModel.togglePrimaryAction()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
        XCTAssertEqual(viewModel.primaryActionTitle, "Pause")
    }

    func testTickCountsDownDuringWorkPhase() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())
        viewModel.togglePrimaryAction()

        viewModel.tick(90)

        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration - 90)
        XCTAssertEqual(viewModel.remainingTimeText, "48:30")
    }

    func testTickDoesNothingWhileIdle() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())

        viewModel.tick(30)

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
    }

    func testWorkPhaseAutomaticallyAdvancesToBreakWhenComplete() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())
        viewModel.togglePrimaryAction()

        viewModel.tick(viewModel.workDuration)

        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(viewModel.remainingTime, viewModel.breakDuration)
    }

    func testBreakPhaseAutomaticallyAdvancesToNextWorkBlockWhenComplete() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())
        viewModel.togglePrimaryAction()
        viewModel.tick(viewModel.workDuration)

        viewModel.tick(viewModel.breakDuration)

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
    }

    func testFullCycleRepeatsWithoutManualRestart() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())
        viewModel.togglePrimaryAction()

        viewModel.tick(viewModel.workDuration)
        XCTAssertEqual(viewModel.phase, .break)

        viewModel.tick(viewModel.breakDuration)
        XCTAssertEqual(viewModel.phase, .work)

        viewModel.tick(viewModel.workDuration)
        XCTAssertEqual(viewModel.phase, .break)
        XCTAssertEqual(viewModel.remainingTime, viewModel.breakDuration)
    }

    func testPauseAndResumeDuringWorkBlock() {
        let viewModel = FocusTimerViewModel(settingsStore: InMemoryTimerSettingsStore())
        viewModel.togglePrimaryAction()
        viewModel.tick(60)

        viewModel.togglePrimaryAction()
        XCTAssertEqual(viewModel.phase, .workPaused)
        XCTAssertEqual(viewModel.primaryActionTitle, "Resume")

        let remainingAtPause = viewModel.remainingTime
        viewModel.tick(60)
        XCTAssertEqual(viewModel.remainingTime, remainingAtPause, "paused timer should not keep counting down")

        viewModel.togglePrimaryAction()
        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, remainingAtPause)
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
}
