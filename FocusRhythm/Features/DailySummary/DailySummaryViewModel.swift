import Foundation
import Observation

@Observable
final class DailySummaryViewModel {
    private(set) var totalFocusTime: TimeInterval = 0
    private(set) var cycleCount: Int = 0
    private(set) var totalWaterMl: Int = 0

    private let sessionStore: FocusSessionStoring
    private let waterLogStore: WaterLogStoring
    private let now: () -> Date

    init(
        sessionStore: FocusSessionStoring = UserDefaultsFocusSessionStore(),
        waterLogStore: WaterLogStoring = UserDefaultsWaterLogStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionStore = sessionStore
        self.waterLogStore = waterLogStore
        self.now = now
        refresh()
    }

    func refresh() {
        let today = now()
        let completedSessions = sessionStore.sessions(on: today).filter(\.completed)

        totalFocusTime = completedSessions.reduce(0) { $0 + $1.duration }
        cycleCount = completedSessions.count
        totalWaterMl = waterLogStore.logs(on: today).reduce(0) { $0 + $1.amountMl }
    }
}
