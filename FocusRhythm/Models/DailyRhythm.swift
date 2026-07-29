import Foundation

struct TimeOfDay: Codable, Equatable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    var isValid: Bool {
        (0..<24).contains(hour) && (0..<60).contains(minute)
    }
}

struct WorkSection: Codable, Equatable, Hashable {
    var startTime: TimeOfDay
    var endTime: TimeOfDay

    init(startTime: TimeOfDay, endTime: TimeOfDay) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct AnchoredLongBreak: Codable, Equatable, Hashable {
    var name: String
    var startTime: TimeOfDay
    var endTime: TimeOfDay

    init(name: String, startTime: TimeOfDay, endTime: TimeOfDay) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
    }
}

enum FinalPartialFocusBehavior: String, Codable, Equatable {
    case omit
    case trim
}

struct DailyRhythm: Codable, Equatable {
    var name: String
    var dayStart: TimeOfDay
    var dayEnd: TimeOfDay
    var workDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var workSections: [WorkSection]
    var longBreaks: [AnchoredLongBreak]
    var finalPartialFocusBehavior: FinalPartialFocusBehavior

    init(
        name: String,
        dayStart: TimeOfDay,
        dayEnd: TimeOfDay,
        workDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        workSections: [WorkSection],
        longBreaks: [AnchoredLongBreak],
        finalPartialFocusBehavior: FinalPartialFocusBehavior = .omit
    ) {
        self.name = name
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.workDuration = workDuration
        self.shortBreakDuration = shortBreakDuration
        self.workSections = workSections
        self.longBreaks = longBreaks
        self.finalPartialFocusBehavior = finalPartialFocusBehavior
    }
}

enum ScheduledIntervalKind: Codable, Equatable {
    case focus
    case shortBreak
    case longBreak(name: String)
}

struct ScheduledInterval: Codable, Equatable {
    let kind: ScheduledIntervalKind
    let startDate: Date
    let endDate: Date
    let isAnchored: Bool

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var isFlexible: Bool {
        !isAnchored
    }
}

struct LongBreakDetails: Equatable {
    let name: String
    let startDate: Date
    let endDate: Date

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

struct GeneratedDailySchedule: Codable, Equatable {
    let rhythmName: String
    let dayStart: Date
    let dayEnd: Date
    let intervals: [ScheduledInterval]

    var expectedFocusTime: TimeInterval {
        intervals
            .filter { $0.kind == .focus }
            .reduce(0) { $0 + $1.duration }
    }

    var focusSessionCount: Int {
        intervals.filter { $0.kind == .focus }.count
    }

    var longBreakDetails: [LongBreakDetails] {
        intervals.compactMap { interval in
            guard case let .longBreak(name) = interval.kind else { return nil }
            return LongBreakDetails(
                name: name,
                startDate: interval.startDate,
                endDate: interval.endDate
            )
        }
    }
}
