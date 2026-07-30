import Foundation

struct RhythmVariation: Codable, Equatable, Identifiable {
    let id: UUID
    var rhythm: DailyRhythm

    init(id: UUID = UUID(), rhythm: DailyRhythm) {
        self.id = id
        self.rhythm = rhythm
    }
}

struct PlannedRhythmSelection: Codable, Equatable {
    let dateKey: String
    let variationID: UUID
}

struct ActiveRhythmRun: Codable, Equatable {
    let variationID: UUID?
    let rhythm: DailyRhythm
    let schedule: GeneratedDailySchedule
    let startedAt: Date
}

enum RunEndMode: String, CaseIterable, Identifiable {
    case stopAt
    case focusFor

    var id: Self { self }
}

enum RunEndCondition: Equatable {
    case stopAt(TimeOfDay)
    case focusFor(TimeInterval)
}

struct RhythmLibrary: Codable, Equatable {
    var variations: [RhythmVariation]
    var defaultVariationID: UUID?
    var plannedSelections: [PlannedRhythmSelection]
    var activeRun: ActiveRhythmRun?

    static let empty = RhythmLibrary(
        variations: [],
        defaultVariationID: nil,
        plannedSelections: [],
        activeRun: nil
    )
}
