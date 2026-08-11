import Foundation
import Observation

/// The single time source used by the app. Release builds always run at wall-clock speed;
/// debug builds can accelerate virtual time while preserving continuous dates when the
/// rate changes.
@Observable
final class AppClock {
    private let wallNow: () -> Date
    private var wallAnchor: Date
    private var virtualAnchor: Date

#if DEBUG
    private(set) var rate: Double
    static let availableRates: [Double] = [1, 10, 60, 120]
#else
    let rate: Double = 1
#endif

    init(wallNow: @escaping () -> Date = Date.init) {
        let anchor = wallNow()
        self.wallNow = wallNow
        self.wallAnchor = anchor
        self.virtualAnchor = anchor
#if DEBUG
        self.rate = 1
#endif
    }

    var now: Date {
        virtualAnchor.addingTimeInterval(wallNow().timeIntervalSince(wallAnchor) * rate)
    }

#if DEBUG
    func setRate(_ newRate: Double) {
        guard Self.availableRates.contains(newRate), newRate != rate else { return }
        let currentVirtualTime = now
        wallAnchor = wallNow()
        virtualAnchor = currentVirtualTime
        rate = newRate
    }
#endif
}
