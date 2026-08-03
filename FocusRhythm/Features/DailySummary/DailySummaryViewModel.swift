import Foundation
import Observation

struct DailyActivitySummary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let plannedDuration: TimeInterval
    let actualDuration: TimeInterval
    let completed: Bool
}

struct DailyRunSummary: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let outcome: CompletedRhythmRun.Outcome
    let plannedFocusTime: TimeInterval
    let plannedCycleCount: Int
    let activities: [DailyActivitySummary]
    let adjustments: [RunAdjustment]
}

@Observable
final class DailySummaryViewModel {
    private(set) var totalFocusTime: TimeInterval = 0
    private(set) var cycleCount: Int = 0
    private(set) var plannedFocusTime: TimeInterval = 0
    private(set) var plannedCycleCount: Int = 0
    private(set) var runOutcome: CompletedRhythmRun.Outcome?
    private(set) var activities: [DailyActivitySummary] = []
    private(set) var adjustments: [RunAdjustment] = []
    private(set) var runSummaries: [DailyRunSummary] = []
    private(set) var totalWaterMl: Int = 0

    private let sessionStore: FocusSessionStoring
    private let waterLogStore: WaterLogStoring
    private let runHistoryStore: RunHistoryStoring
    private let now: () -> Date

    init(
        sessionStore: FocusSessionStoring = UserDefaultsFocusSessionStore(),
        waterLogStore: WaterLogStoring = UserDefaultsWaterLogStore(),
        runHistoryStore: RunHistoryStoring = UserDefaultsRunHistoryStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionStore = sessionStore
        self.waterLogStore = waterLogStore
        self.runHistoryStore = runHistoryStore
        self.now = now
        refresh()
    }

    func refresh() {
        let today = now()
        let sessions = sessionStore.sessions(on: today)
        let uniqueSessions = Dictionary(grouping: sessions) { session in
            "\(session.startedAt.timeIntervalSince1970)|\(session.endedAt.timeIntervalSince1970)|\(session.duration)|\(session.completed)"
        }.compactMap(\.value.first)
        let completedSessions = uniqueSessions.filter(\.completed)
        let runs = runHistoryStore.runs(on: today).sorted { $0.startedAt < $1.startedAt }

        totalFocusTime = uniqueSessions.reduce(0) { $0 + $1.duration }
        cycleCount = completedSessions.count
        plannedFocusTime = runs.reduce(0) { $0 + $1.schedule.expectedFocusTime }
        plannedCycleCount = runs.reduce(0) { $0 + $1.schedule.focusSessionCount }
        runOutcome = runs.count == 1 ? runs.first?.outcome : nil
        runSummaries = runs.map { run in
            let runActivities = run.schedule.intervals.enumerated().compactMap { index, interval -> DailyActivitySummary? in
                guard interval.kind == .focus else { return nil }
                let actual = uniqueSessions.reduce(0) { total, session in
                    let overlapStart = max(session.startedAt, interval.startDate)
                    let overlapEnd = min(session.endedAt, interval.endDate)
                    return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
                }
                let isCompleted = uniqueSessions.contains {
                    $0.completed && $0.startedAt == interval.startDate && $0.endedAt == interval.endDate
                }
                return DailyActivitySummary(
                    id: interval.id,
                    title: interval.label ?? "Focus session \(index + 1)",
                    plannedDuration: interval.duration,
                    actualDuration: actual,
                    completed: isCompleted
                )
            }
            return DailyRunSummary(
                id: run.id,
                startedAt: run.startedAt,
                outcome: run.outcome,
                plannedFocusTime: run.schedule.expectedFocusTime,
                plannedCycleCount: run.schedule.focusSessionCount,
                activities: runActivities,
                adjustments: run.adjustments
            )
        }
        activities = runSummaries.flatMap(\.activities)
        adjustments = runSummaries.flatMap(\.adjustments)
        totalWaterMl = waterLogStore.logs(on: today).reduce(0) { $0 + $1.amountMl }
    }
}
