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

    /// Absolute wall-clock time the current phase ends, kept in sync with `remainingTime`.
    /// Used to recompute `remainingTime` after the app resumes from background and to
    /// schedule the local notification for the transition.
    private(set) var phaseEndTime: Date?

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
    private let notificationScheduler: NotificationScheduling
    private let now: () -> Date
    private var currentWorkStartedAt: Date?

    init(
        phase: FocusPhase = .idle,
        workDuration: TimeInterval? = nil,
        breakDuration: TimeInterval? = nil,
        settingsStore: TimerSettingsStoring = UserDefaultsTimerSettingsStore(),
        sessionStore: FocusSessionStoring = UserDefaultsFocusSessionStore(),
        notificationScheduler: NotificationScheduling = UNUserNotificationScheduler(),
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedWorkDuration = workDuration ?? settingsStore.loadWorkDuration() ?? Self.defaultWorkDuration
        let resolvedBreakDuration = breakDuration ?? settingsStore.loadBreakDuration() ?? Self.defaultBreakDuration

        self.settingsStore = settingsStore
        self.sessionStore = sessionStore
        self.notificationScheduler = notificationScheduler
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
        syncPhaseEndTime()
    }

    /// Advances the countdown by `interval` seconds. Called on a real timer tick in the
    /// running app, and directly with synthetic intervals in tests to avoid real-time waits.
    /// Loops over multiple phase transitions when `interval` spans more than one phase, so
    /// it also serves as the wall-clock catch-up path via `refreshForForeground()`.
    func tick(_ interval: TimeInterval = 1) {
        guard phase.isRunning, !isSelectingBreakDuration else { return }
        var remainingInterval = interval

        while remainingInterval > 0, phase.isRunning, !isSelectingBreakDuration {
            let consumed = min(remainingInterval, remainingTime)
            remainingTime -= consumed
            remainingInterval -= consumed
            guard remainingTime == 0 else { break }

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

        syncPhaseEndTime()
    }

    /// Recomputes `remainingTime` from wall-clock time, catching up through any phase
    /// transitions that should have happened while the app was backgrounded/suspended.
    /// Call on scene-phase becoming active.
    func refreshForForeground() {
        guard phase.isRunning, !isSelectingBreakDuration, let phaseEndTime else { return }
        let secondsPastEnd = now().timeIntervalSince(phaseEndTime)
        guard secondsPastEnd >= 0 else {
            // Still time left; resync precisely in case background time drifted.
            remainingTime = phaseEndTime.timeIntervalSince(now())
            return
        }
        tick(remainingTime + secondsPastEnd)
    }

    /// Adds a one-time bonus chunk (20% of the current phase's original duration) on top
    /// of whatever time remains. Available only once per phase, once 20% time remains.
    func addTime() {
        guard isAddTimeAvailable else { return }
        let bonus = currentPhaseDuration * Self.lowTimeFraction
        remainingTime += bonus
        bonusAdded = bonus
        addTimeUsed = true
        syncPhaseEndTime()
    }

    /// Called when the long-press to interrupt/skip completes (5s during work, 3s during break).
    func completeHoldToInterrupt() {
        switch phase {
        case .work:
            isSelectingBreakDuration = true
            notificationScheduler.cancelPendingPhaseTransition()
        case .break:
            transitionFromBreakToWork()
        case .idle:
            break
        }
    }

    func cancelBreakSelection() {
        isSelectingBreakDuration = false
        syncPhaseEndTime()
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
        syncPhaseEndTime()
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
        syncPhaseEndTime()
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
        syncPhaseEndTime()
        return true
    }

    /// Requests local notification permission. Safe to call repeatedly (e.g. on every
    /// app foreground); the system only prompts the user once.
    func requestNotificationPermission() {
        notificationScheduler.requestAuthorization()
    }

    private func resetAddTime() {
        addTimeUsed = false
        bonusAdded = 0
    }

    /// Keeps `phaseEndTime` in sync with `remainingTime` and (re)schedules or cancels the
    /// local notification for the upcoming phase transition to match.
    private func syncPhaseEndTime() {
        guard phase.isRunning, !isSelectingBreakDuration else {
            phaseEndTime = nil
            notificationScheduler.cancelPendingPhaseTransition()
            return
        }

        let endTime = now().addingTimeInterval(remainingTime)
        phaseEndTime = endTime

        let content = upcomingTransitionNotificationContent
        notificationScheduler.schedulePhaseTransition(at: endTime, title: content.title, body: content.body)
    }

    private var upcomingTransitionNotificationContent: (title: String, body: String) {
        switch phase {
        case .work:
            return ("Break time", "Your focus block is done. Time to drink water.")
        case .break:
            return ("Back to work", "Break's over. Time to start your next focus block.")
        case .idle:
            return ("", "")
        }
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
