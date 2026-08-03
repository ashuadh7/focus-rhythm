import XCTest
@testable import FocusRhythm

final class InMemoryActiveRunStore: ActiveRunStoring {
    var run: ActiveRhythmRun?

    func load() -> ActiveRhythmRun? { run }
    func save(_ run: ActiveRhythmRun) { self.run = run }
    func clear() { run = nil }
}

final class InMemoryRunHistoryStore: RunHistoryStoring {
    private(set) var allRuns: [CompletedRhythmRun] = []
    private let calendar = Calendar.current

    func runs(on date: Date) -> [CompletedRhythmRun] {
        allRuns.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    func record(_ run: CompletedRhythmRun) {
        if let index = allRuns.firstIndex(where: { $0.id == run.id }) {
            allRuns[index] = run
        } else {
            allRuns.append(run)
        }
    }
}

final class ActiveRunStoreTests: XCTestCase {
    func testActiveRunRoundTripsWithRevisionIntervalIdentityAndProgress() {
        let suiteName = "ActiveRunStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsActiveRunStore(defaults: defaults)
        var run = makeRun(start: Date(timeIntervalSince1970: 1_000))
        run.scheduleRevision = 3
        run.recordedIntervalIDs.insert(run.schedule.intervals[0].id)
        run.extendedIntervalIDs.insert(run.schedule.intervals[0].id)

        store.save(run)

        XCTAssertEqual(UserDefaultsActiveRunStore(defaults: defaults).load(), run)
    }

    func testCorruptSavedRunFallsBackSafelyAndRemovesBadData() {
        let suiteName = "ActiveRunStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: "rhythm.active-run.v1")
        let store = UserDefaultsActiveRunStore(defaults: defaults)

        XCTAssertNil(store.load())
        XCTAssertNil(store.load())
    }

    func testRestorerReturnsTodaysUnfinishedRun() {
        let start = Date(timeIntervalSince1970: 10_000)
        let store = InMemoryActiveRunStore()
        store.run = makeRun(start: start)

        let restored = ActiveRunRestorer(
            store: store,
            calendar: utcCalendar,
            now: { start.addingTimeInterval(5 * 60) }
        ).restore()

        XCTAssertEqual(restored, store.run)
    }

    func testRestorerFinalizesRunAfterDayEnd() {
        let start = Date(timeIntervalSince1970: 20_000)
        let store = InMemoryActiveRunStore()
        store.run = makeRun(start: start)
        let sessionStore = InMemoryFocusSessionStore()
        let historyStore = InMemoryRunHistoryStore()

        XCTAssertNil(ActiveRunRestorer(
            store: store,
            sessionStore: sessionStore,
            runHistoryStore: historyStore,
            calendar: utcCalendar,
            now: { start.addingTimeInterval(40 * 60) }
        ).restore())
        XCTAssertEqual(store.run?.status, .completed)
        XCTAssertEqual(store.run?.recordedIntervalIDs.count, 1)
        XCTAssertEqual(sessionStore.allSessions.count, 1)
        XCTAssertEqual(historyStore.allRuns.first?.outcome, .completedAsPlanned)
    }

    func testRestorerDoesNotResumeCompletedRun() {
        let start = Date(timeIntervalSince1970: 30_000)
        let store = InMemoryActiveRunStore()
        var run = makeRun(start: start)
        run.status = .completed
        store.run = run

        XCTAssertNil(ActiveRunRestorer(
            store: store,
            sessionStore: InMemoryFocusSessionStore(),
            calendar: utcCalendar,
            now: { start.addingTimeInterval(5 * 60) }
        ).restore())
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeRun(start: Date) -> ActiveRhythmRun {
        let schedule = GeneratedDailySchedule(
            rhythmName: "Test",
            dayStart: start,
            dayEnd: start.addingTimeInterval(35 * 60),
            intervals: [
                ScheduledInterval(
                    kind: .focus,
                    startDate: start,
                    endDate: start.addingTimeInterval(10 * 60),
                    isAnchored: false
                ),
                ScheduledInterval(
                    kind: .shortBreak,
                    startDate: start.addingTimeInterval(10 * 60),
                    endDate: start.addingTimeInterval(15 * 60),
                    isAnchored: false
                )
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
        return ActiveRhythmRun(
            variationID: nil,
            rhythm: rhythm,
            schedule: schedule,
            startedAt: start
        )
    }
}
