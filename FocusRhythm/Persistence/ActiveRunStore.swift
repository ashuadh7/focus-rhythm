import Foundation

protocol ActiveRunStoring {
    func load() -> ActiveRhythmRun?
    func save(_ run: ActiveRhythmRun)
    func clear()
}

final class UserDefaultsActiveRunStore: ActiveRunStoring {
    private static let key = "rhythm.active-run.v1"
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() -> ActiveRhythmRun? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        guard let run = try? decoder.decode(ActiveRhythmRun.self, from: data) else {
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        return run
    }

    func save(_ run: ActiveRhythmRun) {
        guard let data = try? encoder.encode(run) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

struct ActiveRunRestorer {
    let store: ActiveRunStoring
    let sessionStore: FocusSessionStoring
    let calendar: Calendar
    let now: () -> Date

    init(
        store: ActiveRunStoring = UserDefaultsActiveRunStore(),
        sessionStore: FocusSessionStoring = UserDefaultsFocusSessionStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.sessionStore = sessionStore
        self.calendar = calendar
        self.now = now
    }

    func restore() -> ActiveRhythmRun? {
        guard var run = store.load(), run.status == .active else { return nil }
        let currentDate = now()

        guard calendar.isDate(run.startedAt, inSameDayAs: currentDate),
              calendar.isDate(run.schedule.dayStart, inSameDayAs: currentDate)
        else {
            run.status = .ended
            store.save(run)
            return nil
        }

        guard currentDate < run.schedule.dayEnd else {
            for interval in run.schedule.intervals
            where interval.kind == .focus && !run.recordedIntervalIDs.contains(interval.id) {
                let alreadyRecorded = sessionStore.sessions(on: interval.endDate).contains {
                    $0.completed && $0.startedAt == interval.startDate && $0.endedAt == interval.endDate
                }
                if !alreadyRecorded {
                    sessionStore.addSession(
                        startedAt: interval.startDate,
                        endedAt: interval.endDate,
                        duration: interval.duration,
                        completed: true
                    )
                }
                run.recordedIntervalIDs.insert(interval.id)
            }
            run.status = .completed
            store.save(run)
            return nil
        }

        return run
    }
}
