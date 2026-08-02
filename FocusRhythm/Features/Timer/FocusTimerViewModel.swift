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
    private(set) var scheduleChangeMessage: String?

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
    private var activeRun: ActiveRhythmRun?
    private let activeRunStore: ActiveRunStoring?
    private var schedule: GeneratedDailySchedule? { activeRun?.schedule }
    private var runtimeDate: Date
    private var currentIntervalIndex: Int?

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
        self.activeRun = nil
        self.activeRunStore = nil
        self.runtimeDate = now()
        self.phase = phase
        self.workDuration = resolvedWorkDuration
        self.breakDuration = resolvedBreakDuration
        self.remainingTime = resolvedWorkDuration
        self.currentPhaseDuration = resolvedWorkDuration
    }

    init(
        run: ActiveRhythmRun,
        sessionStore: FocusSessionStoring = UserDefaultsFocusSessionStore(),
        notificationScheduler: NotificationScheduling = UNUserNotificationScheduler(),
        activeRunStore: ActiveRunStoring = UserDefaultsActiveRunStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = UserDefaultsTimerSettingsStore()
        self.sessionStore = sessionStore
        self.notificationScheduler = notificationScheduler
        self.now = now
        self.activeRun = run
        self.activeRunStore = activeRunStore
        self.runtimeDate = now()
        self.phase = .idle
        self.workDuration = run.rhythm.workDuration
        self.breakDuration = run.rhythm.shortBreakDuration
        self.remainingTime = 0
        self.currentPhaseDuration = 0
        reconcileSchedule(at: runtimeDate)
    }

    var phaseTitle: String {
        switch phase {
        case .idle:
            return "Ready"
        case .work:
            return "Focus"
        case .break:
            return "Drink water"
        case .shortBreak:
            return "Short break"
        case let .longBreak(name):
            return name
        case .completedDay:
            return "Day complete"
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
        case .shortBreak:
            return "Drink some water. Focus resumes automatically."
        case .longBreak:
            return "Rest quietly. Your next interval will begin automatically."
        case .completedDay:
            return "Your planned rhythm is complete."
        }
    }

    var dayEnd: Date? { schedule?.dayEnd }
    var isScheduleDriven: Bool { schedule != nil }
    var currentBlockName: String? {
        guard let schedule, let currentIntervalIndex else { return nil }
        return schedule.intervals[currentIntervalIndex].label
    }

    var nextTransition: (title: String, date: Date)? {
        guard let schedule else { return nil }
        guard phase != .completedDay else { return nil }
        if let currentIntervalIndex {
            let nextIndex = currentIntervalIndex + 1
            if schedule.intervals.indices.contains(nextIndex) {
                return (Self.title(for: schedule.intervals[nextIndex].kind), schedule.intervals[nextIndex].startDate)
            }
        } else if let next = schedule.intervals.first(where: { $0.startDate > runtimeDate }) {
            return (Self.title(for: next.kind), next.startDate)
        }
        return ("Day complete", schedule.dayEnd)
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

    var usesSecondScaleBreakPicker: Bool {
        midWorkBreakPickerDefault < 60
    }

    private var lowTimeThreshold: TimeInterval {
        currentPhaseDuration * Self.lowTimeFraction
    }

    var isLowTimeWarningVisible: Bool {
        phase.isRunning && !isSelectingBreakDuration && !addTimeUsed && remainingTime > 0
            && remainingTime <= lowTimeThreshold
    }

    var isAddTimeAvailable: Bool {
        guard isLowTimeWarningVisible else { return false }
        guard let schedule, let currentIntervalIndex else { return true }
        let interval = schedule.intervals[currentIntervalIndex]
        return interval.isFlexible && activeRun?.extendedIntervalIDs.contains(interval.id) != true
    }

    var isBonusLowTimeWarningVisible: Bool {
        phase.isRunning && !isSelectingBreakDuration && addTimeUsed && bonusAdded > 0 && remainingTime > 0
            && remainingTime <= bonusAdded * Self.lowTimeFraction
    }

    /// Starts the first work block. No-op unless idle; there is no short-tap pause/resume —
    /// use `completeHoldToInterrupt` for taking a break or skipping one.
    func start() {
        guard phase == .idle else { return }
        if schedule != nil {
            reconcileSchedule(at: now())
            return
        }
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
        if schedule != nil {
            runtimeDate = runtimeDate.addingTimeInterval(interval)
            reconcileSchedule(at: runtimeDate)
            return
        }
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
            case .idle, .shortBreak, .longBreak, .completedDay:
                break
            }
        }

        syncPhaseEndTime()
    }

    /// Recomputes `remainingTime` from wall-clock time, catching up through any phase
    /// transitions that should have happened while the app was backgrounded/suspended.
    /// Call on scene-phase becoming active.
    func refreshForForeground() {
        if schedule != nil {
            reconcileSchedule(at: now())
            return
        }
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
        if activeRun != nil {
            guard let intervalID = currentIntervalIndex.flatMap({ schedule?.intervals[$0].id }) else { return }
            let applied = reflowRemainingSchedule(by: bonus, from: now())
            guard applied > 0 else { return }
            activeRun?.extendedIntervalIDs.insert(intervalID)
            bonusAdded = applied
            activeRun?.scheduleRevision += 1
            persistActiveRun()
            reconcileSchedule(at: now())
        } else {
            remainingTime += bonus
            bonusAdded = bonus
            syncPhaseEndTime()
        }
        addTimeUsed = true
    }

    /// Called when the long-press to interrupt/skip completes (5s during work, 3s during break).
    func completeHoldToInterrupt() {
        switch phase {
        case .work:
            isSelectingBreakDuration = true
            if activeRun == nil {
                notificationScheduler.cancelTransitionNotifications()
            }
        case .break:
            if activeRun?.quickBreakEndsAt != nil {
                skipScheduledBreak()
            } else {
                transitionFromBreakToWork()
            }
        case .shortBreak:
            skipScheduledBreak()
        case .idle, .longBreak, .completedDay:
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
        if activeRun != nil {
            beginScheduledQuickBreak(duration: cappedDuration)
            return
        }
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
        guard phase != .idle, phase != .completedDay else { return }
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
        if activeRun != nil {
            updateActiveRunStatus(.ended)
        }
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
            notificationScheduler.cancelTransitionNotifications()
            return
        }

        let endTime = now().addingTimeInterval(remainingTime)
        phaseEndTime = endTime

        let content = upcomingTransitionNotificationContent
        notificationScheduler.reconcileTransitionNotifications([
            TransitionNotification(
                identifier: Self.adHocTransitionIdentifier,
                date: endTime,
                title: content.title,
                body: content.body
            )
        ])
    }

    private var upcomingTransitionNotificationContent: (title: String, body: String) {
        switch phase {
        case .work:
            return ("Break time", "Your focus block is done. Time to drink water.")
        case .break:
            return ("Back to work", "Break's over. Time to start your next focus block.")
        case .shortBreak:
            return ("Back to focus", "Your short break is complete.")
        case let .longBreak(name):
            return ("\(name) complete", "Your planned rhythm is continuing.")
        case .idle, .completedDay:
            return ("", "")
        }
    }

    private func reconcileSchedule(at date: Date) {
        guard let schedule else { return }
        let previousIndex = currentIntervalIndex
        let previousPhase = phase
        let previousRecordedCount = activeRun?.recordedIntervalIDs.count
        let previousStatus = activeRun?.status
        runtimeDate = date

        if let quickBreakEndsAt = activeRun?.quickBreakEndsAt {
            if date < quickBreakEndsAt {
                currentIntervalIndex = nil
                phase = .break
                remainingTime = quickBreakEndsAt.timeIntervalSince(date)
                currentPhaseDuration = remainingTime
                phaseEndTime = quickBreakEndsAt
                reconcileDailyRunNotifications(at: date)
                return
            }
            activeRun?.quickBreakEndsAt = nil
            persistActiveRun()
        }

        for interval in schedule.intervals
        where interval.kind == .focus && interval.endDate <= date {
            recordScheduledWorkSession(interval)
        }

        if date >= schedule.dayEnd {
            currentIntervalIndex = nil
            phase = .completedDay
            remainingTime = 0
            currentPhaseDuration = 0
            phaseEndTime = nil
            notificationScheduler.cancelTransitionNotifications()
            updateActiveRunStatus(.completed)
            return
        }

        guard let index = schedule.intervals.firstIndex(where: {
            $0.startDate <= date && date < $0.endDate
        }) else {
            currentIntervalIndex = nil
            phase = .idle
            remainingTime = max(0, (schedule.intervals.first { $0.startDate > date }?.startDate ?? schedule.dayEnd).timeIntervalSince(date))
            currentPhaseDuration = remainingTime
            phaseEndTime = nil
            reconcileDailyRunNotifications(at: date)
            persistActiveRunIfMateriallyChanged(
                previousIndex: previousIndex,
                previousPhase: previousPhase,
                previousRecordedCount: previousRecordedCount,
                previousStatus: previousStatus
            )
            return
        }

        let interval = schedule.intervals[index]
        currentIntervalIndex = index
        phase = Self.phase(for: interval.kind)
        remainingTime = max(0, interval.endDate.timeIntervalSince(date))
        currentPhaseDuration = interval.duration
        phaseEndTime = interval.endDate
        let wasExtended = activeRun?.extendedIntervalIDs.contains(interval.id) == true
        addTimeUsed = wasExtended
        if !wasExtended { bonusAdded = 0 }

        reconcileDailyRunNotifications(at: date)
        persistActiveRunIfMateriallyChanged(
            previousIndex: previousIndex,
            previousPhase: previousPhase,
            previousRecordedCount: previousRecordedCount,
            previousStatus: previousStatus
        )
    }

    private func recordScheduledWorkSession(_ interval: ScheduledInterval) {
        if activeRun?.recordedIntervalIDs.contains(interval.id) == true { return }
        let alreadyRecorded = sessionStore.sessions(on: interval.endDate).contains {
            $0.completed && $0.startedAt == interval.startDate && $0.endedAt == interval.endDate
        }
        if !alreadyRecorded {
            sessionStore.addSession(
                startedAt: interval.startDate,
                endedAt: interval.endDate,
                duration: interval.duration,
                completed: true
            )
        }
        activeRun?.recordedIntervalIDs.insert(interval.id)
    }

    private func updateActiveRunStatus(_ status: ActiveRhythmRun.Status) {
        guard activeRun?.status != status else { return }
        activeRun?.status = status
        if let activeRun {
            activeRunStore?.save(activeRun)
        }
    }

    private func beginScheduledQuickBreak(duration: TimeInterval) {
        let startedAt = now()
        let appliedDuration = reflowRemainingSchedule(
            by: duration,
            from: startedAt,
            excludingAdjustmentFromFocus: true
        )
        guard appliedDuration > 0 else {
            isSelectingBreakDuration = false
            reconcileSchedule(at: startedAt)
            return
        }
        activeRun?.scheduleRevision += 1
        activeRun?.quickBreakEndsAt = startedAt.addingTimeInterval(appliedDuration)
        isSelectingBreakDuration = false
        resetAddTime()
        persistActiveRun()
        reconcileSchedule(at: startedAt)
    }

    @discardableResult
    private func reflowRemainingSchedule(
        by duration: TimeInterval,
        from cutoff: Date,
        excludingAdjustmentFromFocus: Bool = false
    ) -> TimeInterval {
        guard let schedule else { return 0 }
        let oldFocusTime = schedule.expectedFocusTime
        let oldSessionCount = schedule.focusSessionCount
        let result = schedule.reflowingFlexibleRemainder(from: cutoff, by: duration)
        guard result.appliedAdjustment != 0 else { return 0 }
        var revisedSchedule = result.schedule
        if excludingAdjustmentFromFocus,
           let index = revisedSchedule.intervals.firstIndex(where: {
               $0.kind == .focus && $0.startDate <= cutoff && cutoff < $0.endDate
           }) {
            let source = revisedSchedule.intervals[index]
            var intervals = revisedSchedule.intervals
            intervals[index] = ScheduledInterval(
                id: source.id,
                kind: source.kind,
                startDate: source.startDate,
                endDate: source.endDate,
                isAnchored: source.isAnchored,
                label: source.label,
                excludedDuration: source.excludedDuration + result.appliedAdjustment
            )
            revisedSchedule = GeneratedDailySchedule(
                rhythmName: revisedSchedule.rhythmName,
                dayStart: revisedSchedule.dayStart,
                dayEnd: revisedSchedule.dayEnd,
                intervals: intervals
            )
        }
        activeRun?.schedule = revisedSchedule

        let focusDelta = revisedSchedule.expectedFocusTime - oldFocusTime
        let sessionDelta = revisedSchedule.focusSessionCount - oldSessionCount
        let end = schedule.dayEnd.formatted(date: .omitted, time: .shortened)
        if focusDelta < 0 {
            let minutes = Int(abs(focusDelta) / 60)
            let sessionNote = sessionDelta < 0 ? " and removes the final focus interval" : " from the final focus interval"
            scheduleChangeMessage = "This change removes \(minutes) minutes\(sessionNote). The day still ends at \(end)."
        } else {
            scheduleChangeMessage = "The remaining plan moved earlier. The day still ends at \(end)."
        }
        return result.appliedAdjustment
    }

    private func persistActiveRun() {
        if let activeRun {
            activeRunStore?.save(activeRun)
        }
    }

    private func skipScheduledBreak() {
        let skippedAt = now()
        let isSkippingQuickBreak = activeRun?.quickBreakEndsAt != nil
        let remaining = activeRun?.quickBreakEndsAt?.timeIntervalSince(skippedAt) ?? remainingTime
        activeRun?.quickBreakEndsAt = nil
        _ = reflowRemainingSchedule(
            by: -max(0, remaining),
            from: skippedAt,
            excludingAdjustmentFromFocus: isSkippingQuickBreak
        )
        activeRun?.scheduleRevision += 1
        persistActiveRun()
        reconcileSchedule(at: skippedAt)
    }

    private func persistActiveRunIfMateriallyChanged(
        previousIndex: Int?,
        previousPhase: FocusPhase,
        previousRecordedCount: Int?,
        previousStatus: ActiveRhythmRun.Status?
    ) {
        guard previousIndex != currentIntervalIndex
                || previousPhase != phase
                || previousRecordedCount != activeRun?.recordedIntervalIDs.count
                || previousStatus != activeRun?.status,
              let activeRun
        else { return }
        activeRunStore?.save(activeRun)
    }

    private static func phase(for kind: ScheduledIntervalKind) -> FocusPhase {
        switch kind {
        case .focus: return .work
        case .shortBreak: return .shortBreak
        case let .longBreak(name): return .longBreak(name: name)
        }
    }

    private static func title(for kind: ScheduledIntervalKind) -> String {
        switch kind {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case let .longBreak(name): return name
        }
    }

    private static let adHocTransitionIdentifier =
        "\(UNUserNotificationScheduler.transitionIdentifierPrefix)ad-hoc"

    private func reconcileDailyRunNotifications(at date: Date) {
        guard let activeRun else {
            notificationScheduler.cancelTransitionNotifications()
            return
        }

        let runKey = String(Int(activeRun.startedAt.timeIntervalSince1970 * 1_000))
        let revisionKey = "\(runKey).r\(activeRun.scheduleRevision)"
        var notifications = activeRun.schedule.intervals.compactMap { interval -> TransitionNotification? in
            guard interval.startDate > date else { return nil }
            let content = Self.notificationContent(for: interval.kind)
            return TransitionNotification(
                identifier: "\(UNUserNotificationScheduler.transitionIdentifierPrefix)\(revisionKey).interval.\(interval.id.uuidString)",
                date: interval.startDate,
                title: content.title,
                body: content.body
            )
        }

        if let quickBreakEndsAt = activeRun.quickBreakEndsAt, quickBreakEndsAt > date {
            notifications.append(
                TransitionNotification(
                    identifier: "\(UNUserNotificationScheduler.transitionIdentifierPrefix)\(revisionKey).quick-break-end",
                    date: quickBreakEndsAt,
                    title: "Back to focus",
                    body: "Your short pause is complete."
                )
            )
        }

        if activeRun.schedule.dayEnd > date {
            notifications.append(
                TransitionNotification(
                    identifier: "\(UNUserNotificationScheduler.transitionIdentifierPrefix)\(revisionKey).day-end",
                    date: activeRun.schedule.dayEnd,
                    title: "Day complete",
                    body: "Your planned focus rhythm is complete."
                )
            )
        }

        notificationScheduler.reconcileTransitionNotifications(notifications)
    }

    private static func notificationContent(for kind: ScheduledIntervalKind) -> (title: String, body: String) {
        switch kind {
        case .focus:
            return ("Focus resumes", "Your next focus interval begins now.")
        case .shortBreak:
            return ("Short break", "A short pause begins now.")
        case let .longBreak(name):
            return (name, "Your planned long break begins now.")
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
