import XCTest
@testable import FocusRhythm

final class DebugFixtureLoaderTests: XCTestCase {
#if DEBUG
    func testMixedFixtureUsesTransferFormatAndSeedsLocalProgressAndRefreshConflict() throws {
        let fixture = try DebugFixtureLoader(resourceBundle: Bundle(for: Self.self)).makeSnapshot(.mixedOrigin)
        let refreshed = try XCTUnwrap(fixture.nextSourceSnapshot)
        let preview = try fixture.plan.previewingImport(refreshed)

        XCTAssertEqual(fixture.plan.horizon?.endDayExclusive, "2026-10-12")
        XCTAssertTrue(fixture.plan.tasks.contains { $0.id == "literature-x" && $0.sourceID == nil })
        XCTAssertTrue(fixture.plan.tasks.contains { $0.id == "literature-addendum" && $0.parentEstimateAccounting == .addsToParentEstimate })
        XCTAssertTrue(fixture.plan.tasks.contains { $0.id == "unbounded-research" && $0.hasUnknownEstimate })
        XCTAssertEqual(fixture.plan.localState.workSegments.count, 3)
        XCTAssertEqual(fixture.sessions.count, 3)
        XCTAssertEqual(fixture.waterLogs.count, 3)
        XCTAssertTrue(preview.conflicts.contains(.sourceEstimateChanged(taskID: "literature-review")))
    }

    func testLoadingFixtureReplacesDebugScope() throws {
        let suite = "DebugFixtureLoaderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let planStore = UserDefaultsWeeklyPlanStore(defaults: defaults)
        let sessionStore = UserDefaultsFocusSessionStore(defaults: defaults)
        let waterStore = UserDefaultsWaterLogStore(defaults: defaults)
        let loader = DebugFixtureLoader(planStore: planStore, sessionStore: sessionStore, waterStore: waterStore, resourceBundle: Bundle(for: Self.self))
        try planStore.save(WeeklyPlan(id: "old", tasks: []))
        sessionStore.addSession(startedAt: Date(), endedAt: Date().addingTimeInterval(60), duration: 60, completed: true)

        let fixture = try loader.load(.localOnly)

        XCTAssertEqual(planStore.load(), fixture.plan)
        XCTAssertEqual(sessionStore.sessions(on: fixture.startingDate).count, 1)
        XCTAssertEqual(waterStore.logs(on: fixture.startingDate).count, 1)
    }

    func testDateTravelKeepsVirtualClockContinuous() {
        var wall = Date(timeIntervalSince1970: 1_000)
        let clock = AppClock(wallNow: { wall })
        clock.setRate(60)
        clock.travel(days: 3, calendar: Calendar(identifier: .gregorian))
        let travelled = clock.now
        wall = wall.addingTimeInterval(2)

        XCTAssertEqual(clock.now.timeIntervalSince(travelled), 120, accuracy: 0.001)
    }
#endif
}
