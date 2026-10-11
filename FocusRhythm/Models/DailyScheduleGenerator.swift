import Foundation

enum DailyRhythmValidationError: Error, Equatable, LocalizedError {
    case invalidTime(field: String, value: TimeOfDay)
    case nonPositiveDuration(field: String)
    case dayStartMustPrecedeEnd
    case noWorkSections
    case invalidWorkSection(index: Int)
    case workSectionsNotOrderedOrOverlapping(previousIndex: Int, index: Int)
    case workSectionOutsideDay(index: Int)
    case invalidLongBreak(index: Int)
    case invalidSessionsBeforeLongBreak
    case longBreaksNotOrderedOrOverlapping(previousIndex: Int, index: Int)
    case longBreakOutsideDay(index: Int)
    case workSectionOverlapsLongBreak(sectionIndex: Int, longBreakIndex: Int)
    case nonexistentLocalTime(field: String, value: TimeOfDay)

    var errorDescription: String? {
        switch self {
        case let .invalidTime(field, value):
            return "\(field) has invalid time \(value.hour):\(value.minute)."
        case let .nonPositiveDuration(field):
            return "\(field) must be greater than zero."
        case .dayStartMustPrecedeEnd:
            return "Day start must be earlier than day end."
        case .noWorkSections:
            return "At least one work section is required."
        case let .invalidWorkSection(index):
            return "Work section \(index + 1) must start before it ends."
        case let .workSectionsNotOrderedOrOverlapping(previousIndex, index):
            return "Work sections \(previousIndex + 1) and \(index + 1) are out of order or overlap."
        case let .workSectionOutsideDay(index):
            return "Work section \(index + 1) must be contained within the configured day."
        case let .invalidLongBreak(index):
            return "Long break \(index + 1) must start before it ends."
        case .invalidSessionsBeforeLongBreak:
            return "Sessions before a long break must be at least one."
        case let .longBreaksNotOrderedOrOverlapping(previousIndex, index):
            return "Long breaks \(previousIndex + 1) and \(index + 1) are out of order or overlap."
        case let .longBreakOutsideDay(index):
            return "Long break \(index + 1) must be contained within the configured day."
        case let .workSectionOverlapsLongBreak(sectionIndex, longBreakIndex):
            return "Work section \(sectionIndex + 1) overlaps long break \(longBreakIndex + 1)."
        case let .nonexistentLocalTime(field, value):
            return "\(field) time \(value.hour):\(value.minute) does not exist on the requested date."
        }
    }
}

struct DailyScheduleGenerator {
    func generate(
        rhythm: DailyRhythm,
        for date: Date,
        calendar: Calendar
    ) throws -> GeneratedDailySchedule {
        try validate(rhythm)

        let dayStart = try resolve(
            rhythm.dayStart,
            field: "Day start",
            on: date,
            calendar: calendar
        )
        let dayEnd = try resolve(
            rhythm.dayEnd,
            field: "Day end",
            on: date,
            calendar: calendar
        )

        var intervals: [ScheduledInterval] = []

        for (index, section) in rhythm.workSections.enumerated() {
            let start = try resolve(
                section.startTime,
                field: "Work section \(index + 1) start",
                on: date,
                calendar: calendar
            )
            let end = try resolve(
                section.endTime,
                field: "Work section \(index + 1) end",
                on: date,
                calendar: calendar
            )
            intervals.append(contentsOf: fill(sectionFrom: start, to: end, rhythm: rhythm))
        }

        for (index, longBreak) in rhythm.longBreaks.enumerated() {
            let start = try resolve(
                longBreak.startTime,
                field: "Long break \(index + 1) start",
                on: date,
                calendar: calendar
            )
            let end = try resolve(
                longBreak.endTime,
                field: "Long break \(index + 1) end",
                on: date,
                calendar: calendar
            )
            intervals.append(
                ScheduledInterval(
                    kind: .longBreak(name: longBreak.name),
                    startDate: start,
                    endDate: end,
                    isAnchored: true
                )
            )
        }

        intervals.sort { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.endDate < rhs.endDate
            }
            return lhs.startDate < rhs.startDate
        }

        return GeneratedDailySchedule(
            rhythmName: rhythm.name,
            dayStart: dayStart,
            dayEnd: dayEnd,
            intervals: intervals
        )
    }

    /// Regenerates the flexible portion of a rhythm from the current instant while
    /// retaining future anchored breaks and the configured day end.
    func generateStartingNow(
        rhythm: DailyRhythm,
        at now: Date,
        calendar: Calendar
    ) throws -> GeneratedDailySchedule {
        try generateStartingNow(
            rhythm: rhythm,
            at: now,
            endCondition: .stopAt(rhythm.dayEnd),
            calendar: calendar
        )
    }

    func generateStartingNow(
        rhythm: DailyRhythm,
        at now: Date,
        endCondition: RunEndCondition,
        calendar: Calendar
    ) throws -> GeneratedDailySchedule {
        try validate(rhythm)

        switch endCondition {
        case let .stopAt(time):
            let end = try resolve(time, field: "Stop time", on: now, calendar: calendar)
            guard end > now else { throw DailyRhythmValidationError.dayStartMustPrecedeEnd }
            return cadenceSchedule(
                rhythm: rhythm,
                startingAt: now,
                stoppingAt: end
            )
        case let .focusFor(target):
            guard target > 0 else {
                throw DailyRhythmValidationError.nonPositiveDuration(field: "Focus target")
            }
            return cadenceSchedule(
                rhythm: rhythm,
                startingAt: now,
                focusTarget: target
            )
        }
    }

    private func cadenceSchedule(
        rhythm: DailyRhythm,
        startingAt start: Date,
        stoppingAt end: Date? = nil,
        focusTarget: TimeInterval? = nil
    ) -> GeneratedDailySchedule {
        var intervals: [ScheduledInterval] = []
        var cursor = start
        var completedFocus: TimeInterval = 0
        var sessionInCadence = 0

        while true {
            let remainingTarget = focusTarget.map { $0 - completedFocus }
            if let remainingTarget, remainingTarget <= 0 { break }

            let focusDuration = min(rhythm.workDuration, remainingTarget ?? rhythm.workDuration)
            if let end, cursor.addingTimeInterval(focusDuration) > end { break }

            let focusEnd = cursor.addingTimeInterval(focusDuration)
            intervals.append(ScheduledInterval(
                kind: .focus,
                startDate: cursor,
                endDate: focusEnd,
                isAnchored: false
            ))
            cursor = focusEnd
            completedFocus += focusDuration
            sessionInCadence += 1

            if let focusTarget, completedFocus >= focusTarget { break }

            let usesLongBreak = sessionInCadence == rhythm.sessionsBeforeLongBreak
            let breakDuration = usesLongBreak
                ? rhythm.longBreakDuration
                : rhythm.shortBreakDuration

            if let end {
                guard cursor.addingTimeInterval(breakDuration + rhythm.workDuration) <= end
                else { break }
            }

            let breakEnd = cursor.addingTimeInterval(breakDuration)
            intervals.append(ScheduledInterval(
                kind: usesLongBreak ? .longBreak(name: "Long break") : .shortBreak,
                startDate: cursor,
                endDate: breakEnd,
                isAnchored: false,
                label: usesLongBreak ? "Long break" : nil
            ))
            cursor = breakEnd
            if usesLongBreak { sessionInCadence = 0 }
        }

        return GeneratedDailySchedule(
            rhythmName: rhythm.name,
            dayStart: start,
            dayEnd: end ?? cursor,
            intervals: intervals
        )
    }

    func validate(_ rhythm: DailyRhythm) throws {
        let times: [(String, TimeOfDay)] =
            [("Day start", rhythm.dayStart), ("Day end", rhythm.dayEnd)]
            + rhythm.workSections.enumerated().flatMap { index, section in
                [
                    ("Work section \(index + 1) start", section.startTime),
                    ("Work section \(index + 1) end", section.endTime)
                ]
            }
            + rhythm.longBreaks.enumerated().flatMap { index, longBreak in
                [
                    ("Long break \(index + 1) start", longBreak.startTime),
                    ("Long break \(index + 1) end", longBreak.endTime)
                ]
            }

        for (field, time) in times where !time.isValid {
            throw DailyRhythmValidationError.invalidTime(field: field, value: time)
        }
        guard rhythm.workDuration > 0 else {
            throw DailyRhythmValidationError.nonPositiveDuration(field: "Work duration")
        }
        guard rhythm.shortBreakDuration > 0 else {
            throw DailyRhythmValidationError.nonPositiveDuration(field: "Short-break duration")
        }
        guard rhythm.longBreakDuration > 0 else {
            throw DailyRhythmValidationError.nonPositiveDuration(field: "Long-break duration")
        }
        guard rhythm.sessionsBeforeLongBreak > 0 else {
            throw DailyRhythmValidationError.invalidSessionsBeforeLongBreak
        }
        guard rhythm.dayStart < rhythm.dayEnd else {
            throw DailyRhythmValidationError.dayStartMustPrecedeEnd
        }
        guard !rhythm.workSections.isEmpty else {
            throw DailyRhythmValidationError.noWorkSections
        }

        for (index, section) in rhythm.workSections.enumerated() {
            guard section.startTime < section.endTime else {
                throw DailyRhythmValidationError.invalidWorkSection(index: index)
            }
            guard section.startTime >= rhythm.dayStart, section.endTime <= rhythm.dayEnd else {
                throw DailyRhythmValidationError.workSectionOutsideDay(index: index)
            }
            if index > 0 {
                let previous = rhythm.workSections[index - 1]
                guard previous.endTime <= section.startTime else {
                    throw DailyRhythmValidationError.workSectionsNotOrderedOrOverlapping(
                        previousIndex: index - 1,
                        index: index
                    )
                }
            }
        }

        for (index, longBreak) in rhythm.longBreaks.enumerated() {
            guard longBreak.startTime < longBreak.endTime else {
                throw DailyRhythmValidationError.invalidLongBreak(index: index)
            }
            guard longBreak.startTime >= rhythm.dayStart, longBreak.endTime <= rhythm.dayEnd else {
                throw DailyRhythmValidationError.longBreakOutsideDay(index: index)
            }
            if index > 0 {
                let previous = rhythm.longBreaks[index - 1]
                guard previous.endTime <= longBreak.startTime else {
                    throw DailyRhythmValidationError.longBreaksNotOrderedOrOverlapping(
                        previousIndex: index - 1,
                        index: index
                    )
                }
            }

            for (sectionIndex, section) in rhythm.workSections.enumerated()
            where section.startTime < longBreak.endTime && longBreak.startTime < section.endTime {
                throw DailyRhythmValidationError.workSectionOverlapsLongBreak(
                    sectionIndex: sectionIndex,
                    longBreakIndex: index
                )
            }
        }
    }

    private func fill(
        sectionFrom start: Date,
        to end: Date,
        rhythm: DailyRhythm
    ) -> [ScheduledInterval] {
        var result: [ScheduledInterval] = []
        var cursor = start

        while cursor < end {
            let remaining = end.timeIntervalSince(cursor)

            if remaining >= rhythm.workDuration {
                let focusEnd = cursor.addingTimeInterval(rhythm.workDuration)
                result.append(
                    ScheduledInterval(
                        kind: .focus,
                        startDate: cursor,
                        endDate: focusEnd,
                        isAnchored: false
                    )
                )
                cursor = focusEnd

                let afterFocus = end.timeIntervalSince(cursor)
                let canFitAnotherFocus = afterFocus >= rhythm.shortBreakDuration + rhythm.workDuration
                let canFitTrimmedFocus =
                    rhythm.finalPartialFocusBehavior == .trim
                    && afterFocus > rhythm.shortBreakDuration

                guard canFitAnotherFocus || canFitTrimmedFocus else { break }

                let breakEnd = cursor.addingTimeInterval(rhythm.shortBreakDuration)
                result.append(
                    ScheduledInterval(
                        kind: .shortBreak,
                        startDate: cursor,
                        endDate: breakEnd,
                        isAnchored: false
                    )
                )
                cursor = breakEnd
            } else {
                if rhythm.finalPartialFocusBehavior == .trim, remaining > 0 {
                    result.append(
                        ScheduledInterval(
                            kind: .focus,
                            startDate: cursor,
                            endDate: end,
                            isAnchored: false
                        )
                    )
                }
                break
            }
        }

        return result
    }

    private func resolve(
        _ time: TimeOfDay,
        field: String,
        on date: Date,
        calendar: Calendar
    ) throws -> Date {
        let requestedDay = calendar.dateComponents([.era, .year, .month, .day], from: date)
        var components = requestedDay
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0

        guard let resolved = calendar.date(from: components) else {
            throw DailyRhythmValidationError.nonexistentLocalTime(field: field, value: time)
        }

        let resolvedComponents = calendar.dateComponents(
            [.era, .year, .month, .day, .hour, .minute],
            from: resolved
        )
        guard resolvedComponents.era == requestedDay.era,
              resolvedComponents.year == requestedDay.year,
              resolvedComponents.month == requestedDay.month,
              resolvedComponents.day == requestedDay.day,
              resolvedComponents.hour == time.hour,
              resolvedComponents.minute == time.minute else {
            throw DailyRhythmValidationError.nonexistentLocalTime(field: field, value: time)
        }

        return resolved
    }
}
