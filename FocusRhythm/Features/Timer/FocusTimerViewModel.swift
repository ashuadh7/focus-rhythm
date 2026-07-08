import Foundation
import Observation

@Observable
final class FocusTimerViewModel {
    let workDuration: TimeInterval
    let breakDuration: TimeInterval

    private(set) var phase: FocusPhase
    private(set) var remainingTime: TimeInterval

    init(
        phase: FocusPhase = .idle,
        workDuration: TimeInterval = 50 * 60,
        breakDuration: TimeInterval = 10 * 60
    ) {
        self.phase = phase
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        self.remainingTime = workDuration
    }

    var primaryActionTitle: String {
        switch phase {
        case .idle:
            return "Start"
        case .work, .break:
            return "Pause"
        }
    }

    var phaseTitle: String {
        switch phase {
        case .idle:
            return "Ready"
        case .work:
            return "Focus"
        case .break:
            return "Drink water"
        }
    }

    var prompt: String {
        switch phase {
        case .idle:
            return "Settle in for a 50 minute work block."
        case .work:
            return "Protect this block. Break starts automatically."
        case .break:
            return "Log water, then the next work block begins."
        }
    }

    var remainingTimeText: String {
        let clampedTime = max(remainingTime, 0)
        let minutes = Int(clampedTime) / 60
        let seconds = Int(clampedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func togglePrimaryAction() {
        switch phase {
        case .idle:
            phase = .work
            remainingTime = workDuration
        case .work, .break:
            phase = .idle
        }
    }
}
