import Foundation

protocol ActiveRunStoring {
    func load() -> ActiveRhythmRun?
    func save(_ run: ActiveRhythmRun)
    func clear()
}

/// Keeps a compact snapshot of runs that have reached a deliberate end. The active-run
/// record is replaced as a rhythm changes, so it cannot be used to describe a completed
/// day's final plan after a later run begins.
protocol RunHistoryStoring {
    func runs(on date: Date) -> [CompletedRhythmRun]
    func record(_ run: CompletedRhythmRun)
}

struct CompletedRhythmRun: Codable, Equatable, Identifiable {
    enum Outcome: String, Codable, Equatable {
        case completedAsPlanned
        case endedEarly
    }

    let id: UUID
    let startedAt: Date
    let schedule: GeneratedDailySchedule
    let outcome: Outcome
    let adjustments: [RunAdjustment]

    init(id: UUID = UUID(), startedAt: Date, schedule: GeneratedDailySchedule, outcome: Outcome, adjustments: [RunAdjustment] = []) {
        self.id = id
        self.startedAt = startedAt
        self.schedule = schedule
        self.outcome = outcome
        self.adjustments = adjustments
    }
}

final class UserDefaultsRunHistoryStore: RunHistoryStoring {
    private static let key = "rhythm.completed-runs.v1"
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func runs(on date: Date) -> [CompletedRhythmRun] {
        allRuns().filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    func record(_ run: CompletedRhythmRun) {
        var runs = allRuns()
        // A terminal status can be reconciled more than once after restoration. Replace
        // the existing snapshot for that run instead of counting it twice in the summary.
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.append(run)
        }
        guard let data = try? JSONEncoder().encode(runs) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private func allRuns() -> [CompletedRhythmRun] {
        guard let data = defaults.data(forKey: Self.key),
              let runs = try? JSONDecoder().decode([CompletedRhythmRun].self, from: data) else {
            return []
        }
        return runs
    }
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
    let runHistoryStore: RunHistoryStoring
    let calendar: Calendar
    let now: () -> Date

    init(
        store: ActiveRunStoring = UserDefaultsActiveRunStore(),
        sessionStore: FocusSessionStoring = UserDefaultsFocusSessionStore(),
        runHistoryStore: RunHistoryStoring = UserDefaultsRunHistoryStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.sessionStore = sessionStore
        self.runHistoryStore = runHistoryStore
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
            runHistoryStore.record(CompletedRhythmRun(
                id: run.id,
                startedAt: run.startedAt,
                schedule: run.schedule,
                outcome: .endedEarly,
                adjustments: run.adjustments
            ))
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
            runHistoryStore.record(CompletedRhythmRun(
                id: run.id,
                startedAt: run.startedAt,
                schedule: run.schedule,
                outcome: .completedAsPlanned,
                adjustments: run.adjustments
            ))
            return nil
        }

        return run
    }
}
