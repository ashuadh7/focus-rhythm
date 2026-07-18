import Foundation

protocol FocusSessionStoring {
    func sessions(on date: Date) -> [FocusSession]

    @discardableResult
    func addSession(startedAt: Date, endedAt: Date, duration: TimeInterval, completed: Bool) -> FocusSession
}

final class UserDefaultsFocusSessionStore: FocusSessionStoring {
    private enum Key {
        static let sessions = "focus.sessions"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func sessions(on date: Date) -> [FocusSession] {
        allSessions().filter { calendar.isDate($0.endedAt, inSameDayAs: date) }
    }

    @discardableResult
    func addSession(startedAt: Date, endedAt: Date, duration: TimeInterval, completed: Bool) -> FocusSession {
        var sessions = allSessions()
        let session = FocusSession(id: UUID(), startedAt: startedAt, endedAt: endedAt, duration: duration, completed: completed)
        sessions.append(session)
        save(sessions)
        return session
    }

    private func allSessions() -> [FocusSession] {
        guard let data = defaults.data(forKey: Key.sessions),
              let sessions = try? JSONDecoder().decode([FocusSession].self, from: data) else {
            return []
        }
        return sessions
    }

    private func save(_ sessions: [FocusSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Key.sessions)
    }
}
