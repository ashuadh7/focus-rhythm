import XCTest
@testable import FocusRhythm

final class InMemoryWaterLogStore: WaterLogStoring {
    private var entries: [WaterLogEntry] = []
    private let calendar = Calendar.current

    func logs(on date: Date) -> [WaterLogEntry] {
        entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
    }

    @discardableResult
    func addLog(amountMl: Int, date: Date) -> WaterLogEntry {
        let entry = WaterLogEntry(id: UUID(), amountMl: amountMl, loggedAt: date)
        entries.append(entry)
        return entry
    }
}

final class WaterLoggingViewModelTests: XCTestCase {
    func testQuickAmountLogsOneTap() {
        let viewModel = WaterLoggingViewModel(store: InMemoryWaterLogStore(), now: { Date() })

        viewModel.logQuickAmount(250)

        XCTAssertEqual(viewModel.totalLoggedTodayMl, 250)
        XCTAssertEqual(viewModel.todayLogs.count, 1)
    }

    func testMultipleQuickAmountsAccumulate() {
        let viewModel = WaterLoggingViewModel(store: InMemoryWaterLogStore(), now: { Date() })

        viewModel.logQuickAmount(250)
        viewModel.logQuickAmount(500)

        XCTAssertEqual(viewModel.totalLoggedTodayMl, 750)
        XCTAssertEqual(viewModel.todayLogs.count, 2)
    }

    func testCustomAmountLogsWhenValid() {
        let viewModel = WaterLoggingViewModel(store: InMemoryWaterLogStore(), now: { Date() })
        viewModel.customAmountText = "330"

        let logged = viewModel.logCustomAmount()

        XCTAssertTrue(logged)
        XCTAssertEqual(viewModel.totalLoggedTodayMl, 330)
        XCTAssertEqual(viewModel.customAmountText, "")
    }

    func testCustomAmountRejectsInvalidInput() {
        let viewModel = WaterLoggingViewModel(store: InMemoryWaterLogStore(), now: { Date() })
        viewModel.customAmountText = "not a number"

        let logged = viewModel.logCustomAmount()

        XCTAssertFalse(logged)
        XCTAssertEqual(viewModel.totalLoggedTodayMl, 0)
    }

    func testCustomAmountRejectsZeroOrNegative() {
        let viewModel = WaterLoggingViewModel(store: InMemoryWaterLogStore(), now: { Date() })
        viewModel.customAmountText = "0"

        XCTAssertFalse(viewModel.logCustomAmount())
    }

    func testLoadsExistingTodayLogsOnInit() {
        let store = InMemoryWaterLogStore()
        store.addLog(amountMl: 250, date: Date())

        let viewModel = WaterLoggingViewModel(store: store, now: { Date() })

        XCTAssertEqual(viewModel.totalLoggedTodayMl, 250)
    }
}
