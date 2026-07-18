import Foundation
import Observation

@Observable
final class WaterLoggingViewModel {
    static let quickAmountsMl = [250, 500]

    private(set) var todayLogs: [WaterLogEntry] = []
    var customAmountText: String = ""

    private let store: WaterLogStoring
    private let now: () -> Date

    init(store: WaterLogStoring = UserDefaultsWaterLogStore(), now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        refresh()
    }

    var totalLoggedTodayMl: Int {
        todayLogs.reduce(0) { $0 + $1.amountMl }
    }

    func logQuickAmount(_ amountMl: Int) {
        store.addLog(amountMl: amountMl, date: now())
        refresh()
    }

    @discardableResult
    func logCustomAmount() -> Bool {
        guard let amount = Int(customAmountText), amount > 0 else { return false }
        store.addLog(amountMl: amount, date: now())
        customAmountText = ""
        refresh()
        return true
    }

    private func refresh() {
        todayLogs = store.logs(on: now())
    }
}
