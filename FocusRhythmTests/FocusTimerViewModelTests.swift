import XCTest
@testable import FocusRhythm

final class FocusTimerViewModelTests: XCTestCase {
    func testDefaultDurationsMatchMVPDefaults() {
        let viewModel = FocusTimerViewModel()

        XCTAssertEqual(viewModel.workDuration, 50 * 60)
        XCTAssertEqual(viewModel.breakDuration, 10 * 60)
        XCTAssertEqual(viewModel.remainingTimeText, "50:00")
    }

    func testStartingFromIdleBeginsWorkBlock() {
        let viewModel = FocusTimerViewModel()

        viewModel.togglePrimaryAction()

        XCTAssertEqual(viewModel.phase, .work)
        XCTAssertEqual(viewModel.remainingTime, viewModel.workDuration)
        XCTAssertEqual(viewModel.primaryActionTitle, "Pause")
    }
}
