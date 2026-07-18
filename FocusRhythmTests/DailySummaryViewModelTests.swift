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

    func testIncompleteSessionsAreExcludedFromSummary() {
        let sessionStore = InMemoryFocusSessionStore()
        let now = Date()
        sessionStore.addSession(startedAt: now.addingTimeInterval(-600), endedAt: now, duration: 600, completed: false)

        let viewModel = DailySummaryViewModel(sessionStore: sessionStore, waterLogStore: InMemoryWaterLogStore(), now: { now })

        XCTAssertEqual(viewModel.totalFocusTime, 0)
        XCTAssertEqual(viewModel.cycleCount, 0)
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
