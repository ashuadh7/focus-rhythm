import XCTest
@testable import FocusRhythm

final class RhythmLibraryStoreTests: XCTestCase {
    func testMultipleVariationsAndSelectionsSurviveRelaunch() {
        let suiteName = "RhythmLibraryStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsRhythmLibraryStore(defaults: defaults)
        let first = RhythmVariation(rhythm: makeRhythm(name: "WFH"))
        let second = RhythmVariation(rhythm: makeRhythm(name: "College", workMinutes: 25))
        let library = RhythmLibrary(
            variations: [first, second],
            defaultVariationID: second.id,
            plannedSelections: [
                PlannedRhythmSelection(dateKey: "2026-07-27", variationID: first.id)
            ],
            activeRun: nil
        )

        store.save(library)

        XCTAssertEqual(UserDefaultsRhythmLibraryStore(defaults: defaults).load(), library)
    }

    private func makeRhythm(name: String, workMinutes: Int = 50) -> DailyRhythm {
        DailyRhythm(
            name: name,
            dayStart: TimeOfDay(hour: 9, minute: 0),
            dayEnd: TimeOfDay(hour: 17, minute: 0),
            workDuration: TimeInterval(workMinutes * 60),
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
}
