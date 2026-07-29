import XCTest
@testable import FocusRhythm

final class RhythmSetupViewModelTests: XCTestCase {
    func testTodaysPlanIsOfferedBeforeDefault() {
        let context = makeContext()
        let planned = RhythmVariation(rhythm: makeRhythm(name: "Planned"))
        let fallback = RhythmVariation(rhythm: makeRhythm(name: "Default"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [fallback, planned],
            defaultVariationID: fallback.id,
            plannedSelections: [
                PlannedRhythmSelection(dateKey: "2026-07-27", variationID: planned.id)
            ],
            activeRun: nil
        ))

        let viewModel = makeViewModel(store: store, context: context)

        XCTAssertEqual(viewModel.selectedVariationID, planned.id)
        XCTAssertEqual(viewModel.draft.name, "Planned")
    }

    func testDefaultIsSuggestedButCanBeReplacedForToday() {
        let context = makeContext()
        let first = RhythmVariation(rhythm: makeRhythm(name: "First"))
        let fallback = RhythmVariation(rhythm: makeRhythm(name: "Default"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [first, fallback],
            defaultVariationID: fallback.id,
            plannedSelections: [],
            activeRun: nil
        ))
        let viewModel = makeViewModel(store: store, context: context)

        XCTAssertEqual(viewModel.selectedVariationID, fallback.id)
        viewModel.select(first.id)
        viewModel.selectForToday()

        XCTAssertEqual(viewModel.plannedVariationID(for: context.now), first.id)
        XCTAssertEqual(store.library.defaultVariationID, fallback.id)
    }

    func testRunOnlyEditsDoNotModifySavedVariationAndSnapshotIsIndependent() {
        let context = makeContext()
        let variation = RhythmVariation(rhythm: makeRhythm(name: "Saved"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [variation],
            defaultVariationID: nil,
            plannedSelections: [],
            activeRun: nil
        ))
        let viewModel = makeViewModel(store: store, context: context)
        viewModel.draft.name = "One-off"
        viewModel.draft.workDuration = 25 * 60
        viewModel.refreshPreview()

        let run = viewModel.startNow()
        viewModel.draft.name = "Changed later"

        XCTAssertEqual(store.library.variations[0].rhythm.name, "Saved")
        XCTAssertEqual(run?.rhythm.name, "One-off")
        XCTAssertEqual(store.library.activeRun?.rhythm.workDuration, 25 * 60)
    }

    func testSavingUpdatesOnlySelectedVariation() {
        let context = makeContext()
        let first = RhythmVariation(rhythm: makeRhythm(name: "First"))
        let second = RhythmVariation(rhythm: makeRhythm(name: "Second"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [first, second],
            defaultVariationID: nil,
            plannedSelections: [],
            activeRun: nil
        ))
        let viewModel = makeViewModel(store: store, context: context)
        viewModel.draft.name = "Updated"
        viewModel.saveDraftToVariation()

        XCTAssertEqual(store.library.variations[0].rhythm.name, "Updated")
        XCTAssertEqual(store.library.variations[1].rhythm.name, "Second")
    }

    func testStartNowContainsNoElapsedIntervalsAndKeepsFutureAnchorAndDayEnd() {
        let context = makeContext(hour: 10, minute: 15)
        let rhythm = DailyRhythm(
            name: "Day",
            dayStart: TimeOfDay(hour: 9, minute: 0),
            dayEnd: TimeOfDay(hour: 17, minute: 0),
            workDuration: 25 * 60,
            shortBreakDuration: 5 * 60,
            workSections: [
                WorkSection(startTime: TimeOfDay(hour: 9, minute: 0), endTime: TimeOfDay(hour: 12, minute: 0)),
                WorkSection(startTime: TimeOfDay(hour: 13, minute: 0), endTime: TimeOfDay(hour: 17, minute: 0))
            ],
            longBreaks: [
                AnchoredLongBreak(name: "Lunch", startTime: TimeOfDay(hour: 12, minute: 0), endTime: TimeOfDay(hour: 13, minute: 0))
            ]
        )
        let variation = RhythmVariation(rhythm: rhythm)
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [variation],
            defaultVariationID: nil,
            plannedSelections: [],
            activeRun: nil
        ))

        let run = makeViewModel(store: store, context: context).startNow()

        XCTAssertNotNil(run)
        XCTAssertTrue(run!.schedule.intervals.allSatisfy { $0.startDate >= context.now })
        XCTAssertEqual(run!.schedule.longBreakDetails.map(\.name), ["Lunch"])
        XCTAssertEqual(context.calendar.component(.hour, from: run!.schedule.dayEnd), 17)
    }

    func testStandardCascadeStartsAtDayStartAndRepeatsFourHoursWithOneHourBreaks() {
        let context = makeContext()
        let store = MemoryRhythmLibraryStore(.empty)
        let viewModel = makeViewModel(store: store, context: context)
        viewModel.draft.dayStart = TimeOfDay(hour: 7, minute: 30)
        viewModel.draft.dayEnd = TimeOfDay(hour: 17, minute: 30)

        viewModel.applyStandardCascade()

        XCTAssertEqual(viewModel.draft.workSections, [
            WorkSection(
                startTime: TimeOfDay(hour: 7, minute: 30),
                endTime: TimeOfDay(hour: 11, minute: 30)
            ),
            WorkSection(
                startTime: TimeOfDay(hour: 12, minute: 30),
                endTime: TimeOfDay(hour: 17, minute: 30)
            )
        ])
        XCTAssertEqual(viewModel.draft.longBreaks, [
            AnchoredLongBreak(
                name: "Long break 1",
                startTime: TimeOfDay(hour: 11, minute: 30),
                endTime: TimeOfDay(hour: 12, minute: 30)
            )
        ])
    }

    private func makeRhythm(name: String) -> DailyRhythm {
        DailyRhythm(
            name: name,
            dayStart: TimeOfDay(hour: 9, minute: 0),
            dayEnd: TimeOfDay(hour: 17, minute: 0),
            workDuration: 50 * 60,
            shortBreakDuration: 10 * 60,
            workSections: [
                WorkSection(
                    startTime: TimeOfDay(hour: 9, minute: 0),
                    endTime: TimeOfDay(hour: 17, minute: 0)
                )
            ],
            longBreaks: []
        )
    }

    private func makeContext(hour: Int = 8, minute: Int = 0) -> TestContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 27,
            hour: hour,
            minute: minute
        ))!
        return TestContext(calendar: calendar, now: now)
    }

    private func makeViewModel(
        store: MemoryRhythmLibraryStore,
        context: TestContext
    ) -> RhythmSetupViewModel {
        RhythmSetupViewModel(store: store, calendar: context.calendar, now: { context.now })
    }
}

private struct TestContext {
    let calendar: Calendar
    let now: Date
}

private final class MemoryRhythmLibraryStore: RhythmLibraryStoring {
    var library: RhythmLibrary

    init(_ library: RhythmLibrary) {
        self.library = library
    }

    func load() -> RhythmLibrary { library }
    func save(_ library: RhythmLibrary) { self.library = library }
}
