import XCTest
@testable import FocusRhythm

final class InMemoryFocusSessionStore: FocusSessionStoring {
    private(set) var allSessions: [FocusSession] = []
    private let calendar = Calendar.current

    func sessions(on date: Date) -> [FocusSession] {
        allSessions.filter { calendar.isDate($0.endedAt, inSameDayAs: date) }
    }

    @discardableResult
    func addSession(startedAt: Date, endedAt: Date, duration: TimeInterval, completed: Bool) -> FocusSession {
        let session = FocusSession(id: UUID(), startedAt: startedAt, endedAt: endedAt, duration: duration, completed: completed)
        allSessions.append(session)
        return session
    }
}

final class FocusSessionStoreTests: XCTestCase {
    func testAddedSessionIsReturnedForItsDay() {
        let store = InMemoryFocusSessionStore()
        let now = Date()

        store.addSession(startedAt: now.addingTimeInterval(-3000), endedAt: now, duration: 3000, completed: true)

        XCTAssertEqual(store.sessions(on: now).count, 1)
    }

    func testSessionsFromOtherDaysAreExcluded() {
        let store = InMemoryFocusSessionStore()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!

        store.addSession(startedAt: yesterday.addingTimeInterval(-3000), endedAt: yesterday, duration: 3000, completed: true)

        XCTAssertEqual(store.sessions(on: Date()).count, 0)
    }
}
