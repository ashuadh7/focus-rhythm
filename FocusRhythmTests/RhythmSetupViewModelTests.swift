import XCTest
@testable import FocusRhythm

final class RhythmSetupViewModelTests: XCTestCase {
    func testManualTestScenarioIncludesNamedFocusBlocksAndLongBreak() {
        let context = makeContext()
        let store = MemoryRhythmLibraryStore(.empty)
        let activeRunStore = InMemoryActiveRunStore()
        let viewModel = RhythmSetupViewModel(
            store: store,
            activeRunStore: activeRunStore,
            calendar: context.calendar,
            now: { context.now }
        )

        let run = viewModel.startManualTest()

        let focusIntervals = run.schedule.intervals.filter { $0.kind == .focus }
        XCTAssertEqual(focusIntervals.map(\.label), [
            "cs 349 assignment", "Flow-sync", "Throughline", "Grading", "Scholarship"
        ])
        XCTAssertEqual(focusIntervals.map(\.duration), Array(repeating: 20, count: 5))
        XCTAssertEqual(
            run.schedule.intervals.filter { $0.kind == .shortBreak }.map(\.duration),
            Array(repeating: 10, count: 3)
        )
        let longBreaks = run.schedule.intervals.filter {
            if case .longBreak = $0.kind { return true }
            return false
        }
        XCTAssertEqual(longBreaks.map(\.duration), [20])
        XCTAssertEqual(longBreaks.map(\.label), ["Lunch"])
        XCTAssertEqual(run.longBreakWarningTiming, LongBreakWarningTiming(
            wrapUpLeadTime: 10,
            finalReturnLeadTime: 5
        ))
        XCTAssertEqual(run.schedule.dayEnd.timeIntervalSince(run.startedAt), 2 * 60 + 30)
        XCTAssertEqual(activeRunStore.run, run)
    }

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

    func testEditorRunOnlyChoiceCreatesOneTimeRhythmWithoutSaving() {
        let context = makeContext()
        let variation = RhythmVariation(rhythm: makeRhythm(name: "Saved"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [variation],
            defaultVariationID: nil,
            plannedSelections: [],
            activeRun: nil
        ))
        let viewModel = makeViewModel(store: store, context: context)

        viewModel.beginEditingSelected()
        viewModel.draft.workDuration = 25 * 60

        XCTAssertTrue(viewModel.useEditingDraftForThisRun())
        XCTAssertTrue(viewModel.isUsingOneTimeRhythm)
        XCTAssertNil(viewModel.selectedVariationID)
        XCTAssertEqual(store.library.variations[0], variation)
        XCTAssertEqual(viewModel.startNow()?.variationID, nil)
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
        viewModel.beginEditingSelected()
        viewModel.draft.name = "Updated"
        XCTAssertTrue(viewModel.saveEditingDraft())

        XCTAssertEqual(store.library.variations[0].rhythm.name, "Updated")
        XCTAssertEqual(store.library.variations[1].rhythm.name, "Second")
    }

    func testStartNowContainsNoElapsedIntervalsAndUsesCadenceUntilDayEnd() {
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
        XCTAssertEqual(run!.schedule.longBreakDetails.map(\.name), ["Long break"])
        XCTAssertEqual(context.calendar.component(.hour, from: run!.schedule.dayEnd), 17)
    }

    func testStartNowCanUseAFocusTargetInsteadOfAStopTime() {
        let context = makeContext(hour: 9)
        let variation = RhythmVariation(rhythm: makeRhythm(name: "Target"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [variation],
            defaultVariationID: nil,
            plannedSelections: [],
            activeRun: nil
        ))
        let viewModel = makeViewModel(store: store, context: context)
        viewModel.runEndMode = .focusFor
        viewModel.focusTarget = 8 * 60 * 60
        viewModel.refreshRunPreview()

        let run = viewModel.startNow()

        XCTAssertEqual(run?.schedule.dayStart, context.now)
        XCTAssertEqual(run?.schedule.expectedFocusTime, 8 * 60 * 60)
        XCTAssertEqual(viewModel.runPreview?.dayEnd, run?.schedule.dayEnd)
    }

    func testCancellingNewVariationLeavesLibraryAndSelectionUnchanged() {
        let context = makeContext()
        let original = RhythmVariation(rhythm: makeRhythm(name: "Original"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [original],
            defaultVariationID: nil,
            plannedSelections: [],
            activeRun: nil
        ))
        let viewModel = makeViewModel(store: store, context: context)

        viewModel.beginCreatingVariation()
        viewModel.draft.name = "Discard me"

        XCTAssertTrue(viewModel.isCreatingVariation)
        XCTAssertEqual(viewModel.variations.count, 1)

        viewModel.cancelDraftEditing()

        XCTAssertEqual(viewModel.selectedVariationID, original.id)
        XCTAssertEqual(viewModel.draft.name, "Original")
        XCTAssertEqual(store.library.variations, [original])
    }

    func testSavingNewVariationKeepsExistingVariationIndependent() {
        let context = makeContext()
        let original = RhythmVariation(rhythm: makeRhythm(name: "Original"))
        let store = MemoryRhythmLibraryStore(RhythmLibrary(
            variations: [original],
            defaultVariationID: nil,
            plannedSelections: [],
            activeRun: nil
        ))
        let viewModel = makeViewModel(store: store, context: context)

        viewModel.beginCreatingVariation()
        viewModel.draft.name = "Writing"
        viewModel.draft.workDuration = 25 * 60
        viewModel.draft.shortBreakDuration = 5 * 60
        viewModel.draft.longBreakDuration = 30 * 60
        viewModel.draft.sessionsBeforeLongBreak = 3

        XCTAssertTrue(viewModel.saveEditingDraft())
        XCTAssertEqual(store.library.variations.count, 2)
        XCTAssertEqual(store.library.variations[0], original)
        XCTAssertEqual(store.library.variations[1].rhythm.name, "Writing")
        XCTAssertEqual(store.library.variations[1].rhythm.workDuration, 25 * 60)
        XCTAssertEqual(store.library.variations[1].rhythm.longBreakDuration, 30 * 60)
        XCTAssertEqual(store.library.variations[1].rhythm.sessionsBeforeLongBreak, 3)
        XCTAssertEqual(viewModel.selectedVariationID, store.library.variations[1].id)
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
