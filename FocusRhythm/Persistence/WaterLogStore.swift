import Foundation

protocol WaterLogStoring {
    func logs(on date: Date) -> [WaterLogEntry]

    @discardableResult
    func addLog(amountMl: Int, date: Date) -> WaterLogEntry
}

final class UserDefaultsWaterLogStore: WaterLogStoring {
    private enum Key {
        static let entries = "water.logEntries"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func logs(on date: Date) -> [WaterLogEntry] {
        allEntries().filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
    }

    @discardableResult
    func addLog(amountMl: Int, date: Date) -> WaterLogEntry {
        var entries = allEntries()
        let entry = WaterLogEntry(id: UUID(), amountMl: amountMl, loggedAt: date)
        entries.append(entry)
        save(entries)
        return entry
    }

    private func allEntries() -> [WaterLogEntry] {
        guard let data = defaults.data(forKey: Key.entries),
              let entries = try? JSONDecoder().decode([WaterLogEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func save(_ entries: [WaterLogEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Key.entries)
    }
}
