import Foundation
import Observation

@Observable
final class FocusTimerViewModel {
    static let defaultWorkDuration: TimeInterval = 50 * 60
    static let defaultBreakDuration: TimeInterval = 10 * 60

    /// Fraction of a phase's original duration that remains when the low-time warning
    /// appears, and the fraction of the bonus chunk used for the second warning.
    static let lowTimeFraction: TimeInterval = 0.2

    /// Cap on a break taken mid-work (via the interrupt flow), independent of the
    /// configured end-of-work break length.
    static let midWorkBreakCap: TimeInterval = 5 * 60

    /// Minimum number of words required in the end-cycle reasoning before it can be confirmed.
    static let endCycleMinimumWordCount = 20

    private(set) var phase: FocusPhase
    private(set) var remainingTime: TimeInterval
    private(set) var workDuration: TimeInterval
    private(set) var breakDuration: TimeInterval

    /// The original length of the phase currently running (before any add-time bonus).
    /// Differs from `workDuration`/`breakDuration` when the user picked a custom break
    /// length via the interrupt flow.
    private(set) var currentPhaseDuration: TimeInterval
    private(set) var addTimeUsed = false
    private(set) var bonusAdded: TimeInterval = 0

    /// True while the break-length picker is open after a work interrupt. The countdown
    /// freezes during selection.
    private(set) var isSelectingBreakDuration = false

    /// True while the end-cycle confirmation (reasoning prompt) is open.
    private(set) var isEndingCycle = false

    /// Work remaining at the moment a mid-work break was started; restored once that
    /// break ends so work resumes rather than restarting a full block.
    private var pendingWorkRemainder: TimeInterval?

    private let settingsStore: TimerSettingsStoring
    private let sessionStore: FocusSessionStoring
    private let now: () -> Date
    private var currentWorkStartedAt: Date?

    init(
        phase: FocusPhase = .idle,
        workDuration: TimeInterval? = nil,
        breakDuration: TimeInterval? = nil,
        settingsStore: TimerSettingsStoring = UserDefaultsTimerSettingsStore(),
        sessionStore: FocusSessionStoring = UserDefaultsFocusSessionStore(),
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedWorkDuration = workDuration ?? settingsStore.loadWorkDuration() ?? Self.defaultWorkDuration
        let resolvedBreakDuration = breakDuration ?? settingsStore.loadBreakDuration() ?? Self.defaultBreakDuration

        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.now = now
        self.phase = phase
        self.workDuration = resolvedWorkDuration
        self.breakDuration = resolvedBreakDuration
        self.remainingTime = resolvedWorkDuration
        self.currentPhaseDuration = resolvedWorkDuration
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
            return "Settle in for a \(Int(workDuration / 60)) minute work block."
        case .work:
            return "Protect this block. Break starts automatically. Hold to take a break."
        case .break:
            return "Log water, then the next work block begins. Hold to skip."
        }
    }

    var remainingTimeText: String {
        let clampedTime = max(remainingTime, 0)
        let minutes = Int(clampedTime) / 60
        let seconds = Int(clampedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Default/maximum break length to offer in the mid-work interrupt picker.
    var midWorkBreakPickerDefault: TimeInterval {
        min(breakDuration, Self.midWorkBreakCap)
    }

    private var lowTimeThreshold: TimeInterval {
        currentPhaseDuration * Self.lowTimeFraction
    }

    var isLowTimeWarningVisible: Bool {
        phase.isRunning && !isSelectingBreakDuration && !addTimeUsed && remainingTime > 0 && remainingTime <= lowTimeThreshold
    }

    var isAddTimeAvailable: Bool {
        isLowTimeWarningVisible
    }

    var isBonusLowTimeWarningVisible: Bool {
        phase.isRunning && !isSelectingBreakDuration && addTimeUsed && bonusAdded > 0 && remainingTime > 0
            && remainingTime <= bonusAdded * Self.lowTimeFraction
    }

    /// Starts the first work block. No-op unless idle; there is no short-tap pause/resume —
    /// use `completeHoldToInterrupt` for taking a break or skipping one.
    func start() {
        guard phase == .idle else { return }
        phase = .work
        remainingTime = workDuration
        currentPhaseDuration = workDuration
        currentWorkStartedAt = now()
        resetAddTime()
    }

    /// Advances the countdown by `interval` seconds. Called on a real timer tick in the
    /// running app, and directly with synthetic intervals in tests to avoid real-time waits.
    func tick(_ interval: TimeInterval = 1) {
        guard phase.isRunning, !isSelectingBreakDuration else { return }
        remainingTime = max(0, remainingTime - interval)
        guard remainingTime == 0 else { return }

        switch phase {
        case .work:
            recordCompletedWorkSession()
            phase = .break
            remainingTime = breakDuration
            currentPhaseDuration = breakDuration
            resetAddTime()
        case .break:
            transitionFromBreakToWork()
        default:
            break
        }
    }

    /// Adds a one-time bonus chunk (20% of the current phase's original duration) on top
    /// of whatever time remains. Available only once per phase, once 20% time remains.
    func addTime() {
        guard isAddTimeAvailable else { return }
        let bonus = currentPhaseDuration * Self.lowTimeFraction
        remainingTime += bonus
        bonusAdded = bonus
        addTimeUsed = true
    }

    /// Called when the long-press to interrupt/skip completes (5s during work, 3s during break).
    func completeHoldToInterrupt() {
        switch phase {
        case .work:
            isSelectingBreakDuration = true
        case .break:
            transitionFromBreakToWork()
        case .idle:
            break
        }
    }

    func cancelBreakSelection() {
        isSelectingBreakDuration = false
    }

    /// Freezes the current work progress and starts a mid-work break of the chosen length
    /// (capped at `midWorkBreakCap`). Work resumes from the same remaining time once the
    /// break ends — this is a pause, not an abandoned session.
    func confirmBreak(duration: TimeInterval) {
        guard isSelectingBreakDuration else { return }
        let cappedDuration = min(duration, Self.midWorkBreakCap)
        pendingWorkRemainder = remainingTime
        phase = .break
        remainingTime = cappedDuration
        currentPhaseDuration = cappedDuration
        isSelectingBreakDuration = false
        resetAddTime()
    }

    private func transitionFromBreakToWork() {
        phase = .work
        currentPhaseDuration = workDuration
        if let remainder = pendingWorkRemainder {
            remainingTime = remainder
            pendingWorkRemainder = nil
        } else {
            remainingTime = workDuration
            currentWorkStartedAt = now()
        }
        resetAddTime()
    }

    func updateDurations(workDuration: TimeInterval, breakDuration: TimeInterval) {
        self.workDuration = workDuration
        self.breakDuration = breakDuration
        settingsStore.save(workDuration: workDuration, breakDuration: breakDuration)

        if phase == .idle {
            remainingTime = workDuration
            currentPhaseDuration = workDuration
        }
    }

    // MARK: - End cycle

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    func requestEndCycle() {
        guard phase != .idle else { return }
        isEndingCycle = true
    }

    func cancelEndCycle() {
        isEndingCycle = false
    }

    /// Ends the whole cycle and returns to the start screen. Requires at least
    /// `endCycleMinimumWordCount` words of reasoning to discourage impulsive stops.
    @discardableResult
    func confirmEndCycle(reasoning: String) -> Bool {
        guard isEndingCycle, Self.wordCount(reasoning) >= Self.endCycleMinimumWordCount else { return false }

        if phase == .work {
            let elapsed = max(0, workDuration - remainingTime)
            recordInterruptedWorkSession(elapsed: elapsed)
        } else if phase == .break, let remainder = pendingWorkRemainder {
            let elapsed = max(0, workDuration - remainder)
            recordInterruptedWorkSession(elapsed: elapsed)
        }

        phase = .idle
        remainingTime = workDuration
        currentPhaseDuration = workDuration
        pendingWorkRemainder = nil
        currentWorkStartedAt = nil
        isEndingCycle = false
        isSelectingBreakDuration = false
        resetAddTime()
        return true
    }

    private func resetAddTime() {
        addTimeUsed = false
        bonusAdded = 0
    }

    private func recordCompletedWorkSession() {
        let startedAt = currentWorkStartedAt ?? now().addingTimeInterval(-workDuration)
        sessionStore.addSession(startedAt: startedAt, endedAt: now(), duration: workDuration, completed: true)
        currentWorkStartedAt = nil
    }

    private func recordInterruptedWorkSession(elapsed: TimeInterval) {
        let startedAt = currentWorkStartedAt ?? now().addingTimeInterval(-elapsed)
        sessionStore.addSession(startedAt: startedAt, endedAt: now(), duration: elapsed, completed: false)
        currentWorkStartedAt = nil
    }
}
