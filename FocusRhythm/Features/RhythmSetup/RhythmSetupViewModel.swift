import Foundation
import Observation

@Observable
final class RhythmSetupViewModel {
    private(set) var library: RhythmLibrary
    private(set) var selectedVariationID: UUID?
    var draft: DailyRhythm
    private(set) var preview: GeneratedDailySchedule?
    private(set) var validationMessage: String?

    private let store: RhythmLibraryStoring
    private let generator: DailyScheduleGenerator
    private let calendar: Calendar
    private let now: () -> Date

    init(
        store: RhythmLibraryStoring = UserDefaultsRhythmLibraryStore(),
        generator: DailyScheduleGenerator = DailyScheduleGenerator(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.generator = generator
        self.calendar = calendar
        self.now = now
        let library = store.load()
        self.library = library

        let today = now()
        let dateKey = Self.dateKey(for: today, calendar: calendar)
        let plannedID = library.plannedSelections.first { $0.dateKey == dateKey }?.variationID
        let initialID = plannedID.flatMap { id in library.variations.contains { $0.id == id } ? id : nil }
            ?? library.defaultVariationID.flatMap { id in library.variations.contains { $0.id == id } ? id : nil }
            ?? library.variations.first?.id
        self.selectedVariationID = initialID
        self.draft = library.variations.first { $0.id == initialID }?.rhythm ?? Self.exampleRhythm
        refreshPreview()
    }

    var variations: [RhythmVariation] { library.variations }

    var selectedVariation: RhythmVariation? {
        library.variations.first { $0.id == selectedVariationID }
    }

    var isDraftModified: Bool {
        guard let selectedVariation else { return true }
        return draft != selectedVariation.rhythm
    }

    var isSelectedDefault: Bool {
        selectedVariationID != nil && selectedVariationID == library.defaultVariationID
    }

    var isSelectedForToday: Bool {
        guard let selectedVariationID else { return false }
        return plannedVariationID(for: now()) == selectedVariationID
    }

    var canStart: Bool {
        preview != nil && validationMessage == nil
    }

    func select(_ id: UUID) {
        guard let variation = library.variations.first(where: { $0.id == id }) else { return }
        selectedVariationID = id
        draft = variation.rhythm
        refreshPreview()
    }

    func createVariation() {
        var rhythm = Self.exampleRhythm
        Self.applyStandardCascade(to: &rhythm)
        let variation = RhythmVariation(rhythm: rhythm)
        library.variations.append(variation)
        selectedVariationID = variation.id
        draft = variation.rhythm
        persist()
        refreshPreview()
    }

    func duplicateSelected() {
        guard var rhythm = selectedVariation?.rhythm else { return }
        rhythm.name += " copy"
        let variation = RhythmVariation(rhythm: rhythm)
        library.variations.append(variation)
        selectedVariationID = variation.id
        draft = rhythm
        persist()
        refreshPreview()
    }

    func deleteSelected() {
        guard let id = selectedVariationID else { return }
        library.variations.removeAll { $0.id == id }
        library.plannedSelections.removeAll { $0.variationID == id }
        if library.defaultVariationID == id { library.defaultVariationID = nil }
        selectedVariationID = library.variations.first?.id
        draft = selectedVariation?.rhythm ?? Self.exampleRhythm
        persist()
        refreshPreview()
    }

    func saveDraftToVariation() {
        guard let id = selectedVariationID,
              let index = library.variations.firstIndex(where: { $0.id == id }) else { return }
        do {
            try generator.validate(draft)
            library.variations[index].rhythm = draft
            validationMessage = nil
            persist()
            refreshPreview()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    func discardDraftChanges() {
        guard let rhythm = selectedVariation?.rhythm else { return }
        draft = rhythm
        refreshPreview()
    }

    func toggleDefault() {
        guard let id = selectedVariationID else { return }
        library.defaultVariationID = library.defaultVariationID == id ? nil : id
        persist()
    }

    func selectForToday() {
        guard let id = selectedVariationID else { return }
        plan(id, for: now())
    }

    func plan(_ variationID: UUID, for date: Date) {
        guard library.variations.contains(where: { $0.id == variationID }) else { return }
        let key = Self.dateKey(for: date, calendar: calendar)
        library.plannedSelections.removeAll { $0.dateKey == key }
        library.plannedSelections.append(PlannedRhythmSelection(dateKey: key, variationID: variationID))
        persist()
    }

    func plannedVariationID(for date: Date) -> UUID? {
        let key = Self.dateKey(for: date, calendar: calendar)
        return library.plannedSelections.first { $0.dateKey == key }?.variationID
    }

    func refreshPreview() {
        do {
            preview = try generator.generate(rhythm: draft, for: now(), calendar: calendar)
            validationMessage = nil
        } catch {
            preview = nil
            validationMessage = error.localizedDescription
        }
    }

    func applyStandardCascade() {
        Self.applyStandardCascade(to: &draft)
        refreshPreview()
    }

    /// Creates and persists a value snapshot. The draft can be a saved edit or a run-only edit;
    /// either way, later library changes cannot mutate this run.
    @discardableResult
    func startNow() -> ActiveRhythmRun? {
        do {
            let startedAt = now()
            let schedule = try generator.generateStartingNow(
                rhythm: draft,
                at: startedAt,
                calendar: calendar
            )
            let run = ActiveRhythmRun(
                variationID: selectedVariationID,
                rhythm: draft,
                schedule: schedule,
                startedAt: startedAt
            )
            library.activeRun = run
            persist()
            validationMessage = nil
            return run
        } catch {
            validationMessage = error.localizedDescription
            return nil
        }
    }

    private func persist() {
        store.save(library)
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func applyStandardCascade(to rhythm: inout DailyRhythm) {
        let start = rhythm.dayStart.hour * 60 + rhythm.dayStart.minute
        let end = rhythm.dayEnd.hour * 60 + rhythm.dayEnd.minute
        guard start < end else {
            rhythm.workSections = []
            rhythm.longBreaks = []
            return
        }

        let workLength = 4 * 60
        let breakLength = 60
        var cursor = start
        var sectionIndex = 1
        var sections: [WorkSection] = []
        var breaks: [AnchoredLongBreak] = []

        while cursor < end {
            var workEnd = min(cursor + workLength, end)
            if workEnd < end, workEnd + breakLength >= end {
                workEnd = end
            }
            sections.append(WorkSection(
                startTime: time(from: cursor),
                endTime: time(from: workEnd)
            ))
            guard workEnd + breakLength < end else { break }

            let breakEnd = workEnd + breakLength
            breaks.append(AnchoredLongBreak(
                name: "Long break \(sectionIndex)",
                startTime: time(from: workEnd),
                endTime: time(from: breakEnd)
            ))
            cursor = breakEnd
            sectionIndex += 1
        }

        rhythm.workSections = sections
        rhythm.longBreaks = breaks
    }

    private static func time(from minutes: Int) -> TimeOfDay {
        TimeOfDay(hour: minutes / 60, minute: minutes % 60)
    }

    static let exampleRhythm = DailyRhythm(
        name: "My day",
        dayStart: TimeOfDay(hour: 9, minute: 0),
        dayEnd: TimeOfDay(hour: 17, minute: 0),
        workDuration: 50 * 60,
        shortBreakDuration: 10 * 60,
        workSections: [
            WorkSection(
                startTime: TimeOfDay(hour: 9, minute: 0),
                endTime: TimeOfDay(hour: 13, minute: 0)
            ),
            WorkSection(
                startTime: TimeOfDay(hour: 14, minute: 0),
                endTime: TimeOfDay(hour: 17, minute: 0)
            )
        ],
        longBreaks: [
            AnchoredLongBreak(
                name: "Lunch",
                startTime: TimeOfDay(hour: 13, minute: 0),
                endTime: TimeOfDay(hour: 14, minute: 0)
            )
        ]
    )
}
