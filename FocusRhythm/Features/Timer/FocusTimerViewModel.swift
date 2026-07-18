import Foundation
import Observation

@Observable
final class FocusTimerViewModel {
    static let defaultWorkDuration: TimeInterval = 50 * 60
    static let defaultBreakDuration: TimeInterval = 10 * 60

    private(set) var phase: FocusPhase
    private(set) var remainingTime: TimeInterval
    private(set) var workDuration: TimeInterval
    private(set) var breakDuration: TimeInterval

    private let settingsStore: TimerSettingsStoring

    init(
        phase: FocusPhase = .idle,
        workDuration: TimeInterval? = nil,
        breakDuration: TimeInterval? = nil,
        settingsStore: TimerSettingsStoring = UserDefaultsTimerSettingsStore()
    ) {
        let resolvedWorkDuration = workDuration ?? settingsStore.loadWorkDuration() ?? Self.defaultWorkDuration
        let resolvedBreakDuration = breakDuration ?? settingsStore.loadBreakDuration() ?? Self.defaultBreakDuration

        self.settingsStore = settingsStore
        self.phase = phase
        self.workDuration = resolvedWorkDuration
        self.breakDuration = resolvedBreakDuration
        self.remainingTime = resolvedWorkDuration
    }

    var primaryActionTitle: String {
        switch phase {
        case .idle:
            return "Start"
        case .work, .break:
            return "Pause"
        case .workPaused, .breakPaused:
            return "Resume"
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
        case .workPaused:
            return "Focus (paused)"
        case .breakPaused:
            return "Break (paused)"
        }
    }

    var prompt: String {
        switch phase {
        case .idle:
            return "Settle in for a \(Int(workDuration / 60)) minute work block."
        case .work:
            return "Protect this block. Break starts automatically."
        case .break:
            return "Log water, then the next work block begins."
        case .workPaused, .breakPaused:
            return "Paused. Resume when you're ready."
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
        case .work:
            phase = .workPaused
        case .break:
            phase = .breakPaused
        case .workPaused:
            phase = .work
        case .breakPaused:
            phase = .break
        }
    }

    /// Advances the countdown by `interval` seconds. Called on a real timer tick in the
    /// running app, and directly with synthetic intervals in tests to avoid real-time waits.
    func tick(_ interval: TimeInterval = 1) {
        guard phase.isRunning else { return }
        remainingTime = max(0, remainingTime - interval)
        guard remainingTime == 0 else { return }

        switch phase {
        case .work:
            phase = .break
            remainingTime = breakDuration
        case .break:
            phase = .work
            remainingTime = workDuration
        default:
            break
        }
    }

    func updateDurations(workDuration: TimeInterval, breakDuration: TimeInterval) {
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        settingsStore.save(workDuration: workDuration, breakDuration: breakDuration)

        if phase == .idle {
            remainingTime = workDuration
        }
    }
}
