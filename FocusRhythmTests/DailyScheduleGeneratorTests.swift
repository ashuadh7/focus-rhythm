import XCTest
@testable import FocusRhythm

final class DailyScheduleGeneratorTests: XCTestCase {
    private let generator = DailyScheduleGenerator()

    func testSameInputsGenerateSameSchedule() throws {
        let rhythm = makeRhythm()
        let calendar = makeCalendar()
        let date = makeDate(year: 2026, month: 7, day: 27, calendar: calendar)

        let first = try generator.generate(rhythm: rhythm, for: date, calendar: calendar)
        let second = try generator.generate(rhythm: rhythm, for: date, calendar: calendar)

        XCTAssertEqual(first, second)
    }

    func testMultipleSectionsAndAnchoredLongBreakGenerateOrderedSchedule() throws {
        let rhythm = makeRhythm(
            sections: [
                section(9, 0, 11, 0),
                section(12, 0, 14, 0)
            ],
            longBreaks: [
                AnchoredLongBreak(
                    name: "Lunch",
                    startTime: time(11, 0),
                    endTime: time(12, 0)
                )
            ]
        )

        let schedule = try generate(rhythm)

        XCTAssertEqual(schedule.intervals.map(\.kind), [
            .focus, .shortBreak, .focus,
            .longBreak(name: "Lunch"),
            .focus, .shortBreak, .focus
        ])
        XCTAssertTrue(zip(schedule.intervals, schedule.intervals.dropFirst()).allSatisfy { pair in
            pair.0.endDate <= pair.1.startDate
        })
        XCTAssertTrue(schedule.intervals.allSatisfy {
            $0.startDate >= schedule.dayStart && $0.endDate <= schedule.dayEnd
        })
        XCTAssertEqual(schedule.expectedFocusTime, 200 * 60)
        XCTAssertEqual(schedule.focusSessionCount, 4)
        XCTAssertEqual(schedule.longBreakDetails.map(\.name), ["Lunch"])
        XCTAssertEqual(schedule.longBreakDetails.first?.duration, 60 * 60)
        XCTAssertTrue(schedule.intervals.filter { $0.kind == .focus }.allSatisfy(\.isFlexible))
        XCTAssertTrue(schedule.intervals.first { $0.kind == .longBreak(name: "Lunch") }?.isAnchored == true)
    }

    func testOmitBehaviorDropsIncompleteFocusAndDoesNotLeaveTrailingBreak() throws {
        let rhythm = makeRhythm(
            workDuration: 50 * 60,
            shortBreakDuration: 10 * 60,
            sections: [section(9, 0, 10, 35)],
            partialBehavior: .omit
        )

        let schedule = try generate(rhythm)

        XCTAssertEqual(schedule.intervals.map(\.kind), [.focus])
        XCTAssertEqual(schedule.expectedFocusTime, 50 * 60)
    }

    func testTrimBehaviorPreservesFullBreakAndTrimsFinalFocus() throws {
        let rhythm = makeRhythm(
            workDuration: 50 * 60,
            shortBreakDuration: 10 * 60,
            sections: [section(9, 0, 10, 35)],
            partialBehavior: .trim
        )

        let schedule = try generate(rhythm)

        XCTAssertEqual(schedule.intervals.map(\.kind), [.focus, .shortBreak, .focus])
        XCTAssertEqual(schedule.intervals[1].duration, 10 * 60)
        XCTAssertEqual(schedule.intervals[2].duration, 35 * 60)
        XCTAssertEqual(schedule.expectedFocusTime, 85 * 60)
    }

    func testTightSectionCanProduceOneTrimmedFocusInterval() throws {
        let rhythm = makeRhythm(
            sections: [section(9, 0, 9, 20)],
            partialBehavior: .trim
        )

        let schedule = try generate(rhythm)

        XCTAssertEqual(schedule.intervals.map(\.kind), [.focus])
        XCTAssertEqual(schedule.intervals.first?.duration, 20 * 60)
    }

    func testTightSectionCanBeEmptyWhenPartialFocusIsOmitted() throws {
        let rhythm = makeRhythm(
            sections: [section(9, 0, 9, 20)],
            partialBehavior: .omit
        )

        let schedule = try generate(rhythm)

        XCTAssertTrue(schedule.intervals.isEmpty)
        XCTAssertEqual(schedule.expectedFocusTime, 0)
        XCTAssertEqual(schedule.focusSessionCount, 0)
    }

    func testConfiguredDayAndAnchorTimesAreRetained() throws {
        let rhythm = makeRhythm(
            sections: [section(9, 0, 11, 0)],
            longBreaks: [
                AnchoredLongBreak(name: "Lunch", startTime: time(12, 15), endTime: time(13, 5))
            ]
        )
        let calendar = makeCalendar()

        let schedule = try generate(rhythm, calendar: calendar)

        XCTAssertEqual(clockTime(schedule.dayEnd, calendar: calendar), time(18, 0))
        XCTAssertEqual(clockTime(schedule.longBreakDetails[0].startDate, calendar: calendar), time(12, 15))
        XCTAssertEqual(clockTime(schedule.longBreakDetails[0].endDate, calendar: calendar), time(13, 5))
    }

    func testGenerationUsesRequestedCalendarDayAndTimeZone() throws {
        let rhythm = makeRhythm(sections: [section(9, 0, 10, 0)])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let input = makeDate(year: 2026, month: 12, day: 31, hour: 23, calendar: calendar)

        let schedule = try generator.generate(rhythm: rhythm, for: input, calendar: calendar)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: schedule.dayStart
        )

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 0)
    }

    func testNonexistentDayBoundaryTimeReturnsUsefulError() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let date = makeDate(year: 2026, month: 3, day: 8, calendar: calendar)
        let rhythm = makeRhythm(
            dayStart: time(2, 30),
            sections: [section(3, 0, 4, 0)]
        )

        XCTAssertThrowsError(try generator.generate(rhythm: rhythm, for: date, calendar: calendar)) {
            XCTAssertEqual(
                $0 as? DailyRhythmValidationError,
                .nonexistentLocalTime(field: "Day start", value: self.time(2, 30))
            )
        }
    }

    func testValidationRejectsInvalidDurations() {
        assertValidationError(
            makeRhythm(workDuration: 0),
            equals: .nonPositiveDuration(field: "Work duration")
        )
        assertValidationError(
            makeRhythm(shortBreakDuration: -1),
            equals: .nonPositiveDuration(field: "Short-break duration")
        )
    }

    func testValidationRejectsStartAtOrAfterEnd() {
        assertValidationError(
            makeRhythm(dayStart: time(18, 0), dayEnd: time(8, 0)),
            equals: .dayStartMustPrecedeEnd
        )
    }

    func testValidationRejectsMissingWorkSections() {
        assertValidationError(makeRhythm(sections: []), equals: .noWorkSections)
    }

    func testValidationRejectsOverlappingWorkSections() {
        let rhythm = makeRhythm(sections: [
            section(9, 0, 12, 0),
            section(11, 0, 13, 0)
        ])

        assertValidationError(
            rhythm,
            equals: .workSectionsNotOrderedOrOverlapping(previousIndex: 0, index: 1)
        )
    }

    func testValidationRejectsUnorderedOrOverlappingAnchors() {
        let rhythm = makeRhythm(
            sections: [section(9, 0, 10, 0)],
            longBreaks: [
                AnchoredLongBreak(name: "Later", startTime: time(14, 0), endTime: time(15, 0)),
                AnchoredLongBreak(name: "Earlier", startTime: time(12, 0), endTime: time(13, 0))
            ]
        )

        assertValidationError(
            rhythm,
            equals: .longBreaksNotOrderedOrOverlapping(previousIndex: 0, index: 1)
        )
    }

    func testValidationRejectsSectionsAndAnchorsOutsideDay() {
        assertValidationError(
            makeRhythm(sections: [section(7, 0, 9, 0)]),
            equals: .workSectionOutsideDay(index: 0)
        )
        assertValidationError(
            makeRhythm(
                sections: [section(9, 0, 10, 0)],
                longBreaks: [
                    AnchoredLongBreak(name: "Late", startTime: time(17, 30), endTime: time(18, 30))
                ]
            ),
            equals: .longBreakOutsideDay(index: 0)
        )
    }

    func testValidationRejectsWorkOverlappingAnAnchor() {
        let rhythm = makeRhythm(
            sections: [section(9, 0, 12, 30)],
            longBreaks: [
                AnchoredLongBreak(name: "Lunch", startTime: time(12, 0), endTime: time(13, 0))
            ]
        )

        assertValidationError(
            rhythm,
            equals: .workSectionOverlapsLongBreak(sectionIndex: 0, longBreakIndex: 0)
        )
    }

    private func makeRhythm(
        dayStart: TimeOfDay = TimeOfDay(hour: 8, minute: 0),
        dayEnd: TimeOfDay = TimeOfDay(hour: 18, minute: 0),
        workDuration: TimeInterval = 50 * 60,
        shortBreakDuration: TimeInterval = 10 * 60,
        sections: [WorkSection] = [WorkSection(
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 11, minute: 0)
        )],
        longBreaks: [AnchoredLongBreak] = [],
        partialBehavior: FinalPartialFocusBehavior = .omit
    ) -> DailyRhythm {
        DailyRhythm(
            name: "Normal day",
            dayStart: dayStart,
            dayEnd: dayEnd,
            workDuration: workDuration,
            shortBreakDuration: shortBreakDuration,
            workSections: sections,
            longBreaks: longBreaks,
            finalPartialFocusBehavior: partialBehavior
        )
    }

    private func generate(
        _ rhythm: DailyRhythm,
        calendar: Calendar = DailyScheduleGeneratorTests.makeCalendar()
    ) throws -> GeneratedDailySchedule {
        let date = makeDate(year: 2026, month: 7, day: 27, calendar: calendar)
        return try generator.generate(rhythm: rhythm, for: date, calendar: calendar)
    }

    private func assertValidationError(
        _ rhythm: DailyRhythm,
        equals expected: DailyRhythmValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try generator.validate(rhythm), file: file, line: line) {
            XCTAssertEqual($0 as? DailyRhythmValidationError, expected, file: file, line: line)
        }
    }

    private func time(_ hour: Int, _ minute: Int) -> TimeOfDay {
        TimeOfDay(hour: hour, minute: minute)
    }

    private func section(
        _ startHour: Int,
        _ startMinute: Int,
        _ endHour: Int,
        _ endMinute: Int
    ) -> WorkSection {
        WorkSection(
            startTime: time(startHour, startMinute),
            endTime: time(endHour, endMinute)
        )
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeCalendar() -> Calendar {
        Self.makeCalendar()
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func clockTime(_ date: Date, calendar: Calendar) -> TimeOfDay {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour!, minute: components.minute!)
    }
}
