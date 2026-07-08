import Foundation

protocol TimerSettingsStoring {
    func loadWorkDuration() -> TimeInterval?
    func loadBreakDuration() -> TimeInterval?
    func save(workDuration: TimeInterval, breakDuration: TimeInterval)
}

final class UserDefaultsTimerSettingsStore: TimerSettingsStoring {
    private enum Key {
        static let workDuration = "timer.workDuration"
        static let breakDuration = "timer.breakDuration"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadWorkDuration() -> TimeInterval? {
        defaults.object(forKey: Key.workDuration) as? TimeInterval
    }

    func loadBreakDuration() -> TimeInterval? {
        defaults.object(forKey: Key.breakDuration) as? TimeInterval
    }

    func save(workDuration: TimeInterval, breakDuration: TimeInterval) {
        defaults.set(workDuration, forKey: Key.workDuration)
        defaults.set(breakDuration, forKey: Key.breakDuration)
    }
}
