import Foundation

#if DEBUG
enum DebugFixtureKind: String, CaseIterable, Identifiable {
    case localOnly
    case mixedOrigin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localOnly: return "Local-only day 1"
        case .mixedOrigin: return "Imported + local day 1"
        }
    }
}

struct DebugFixtureSnapshot {
    let startingDate: Date
    let plan: WeeklyPlan
    /// The next source snapshot deliberately changes an imported estimate while the
    /// saved plan has local child work. Import tests use it to exercise review.
    let nextSourceSnapshot: WeeklyPlan?
    let sessions: [FocusSession]
    let waterLogs: [WaterLogEntry]
}

/// Debug fixtures go through the same Codable transfer format and durable stores as
/// production data. Loading one is intentionally destructive and is only invoked
/// after the app's explicit confirmation dialog.
struct DebugFixtureLoader {
    private let planStore: UserDefaultsWeeklyPlanStore
    private let sessionStore: UserDefaultsFocusSessionStore
    private let waterStore: UserDefaultsWaterLogStore
    private let activeRunStore: UserDefaultsActiveRunStore
    private let stoppedRunStore: UserDefaultsStoppedRunStore
    private let resourceBundle: Bundle

    init(
        planStore: UserDefaultsWeeklyPlanStore = UserDefaultsWeeklyPlanStore(),
        sessionStore: UserDefaultsFocusSessionStore = UserDefaultsFocusSessionStore(),
        waterStore: UserDefaultsWaterLogStore = UserDefaultsWaterLogStore(),
        activeRunStore: UserDefaultsActiveRunStore = UserDefaultsActiveRunStore(),
        stoppedRunStore: UserDefaultsStoppedRunStore = UserDefaultsStoppedRunStore(),
        resourceBundle: Bundle = .main
    ) {
        self.planStore = planStore
        self.sessionStore = sessionStore
        self.waterStore = waterStore
        self.activeRunStore = activeRunStore
        self.stoppedRunStore = stoppedRunStore
        self.resourceBundle = resourceBundle
    }

    @discardableResult
    func load(_ kind: DebugFixtureKind) throws -> DebugFixtureSnapshot {
        let snapshot = try makeSnapshot(kind)
        // Validation/encoding completes before the existing catalog is replaced.
        try planStore.save(snapshot.plan)
        sessionStore.replaceForDebugFixture(snapshot.sessions)
        waterStore.replaceForDebugFixture(snapshot.waterLogs)
        activeRunStore.clear()
        stoppedRunStore.clear()
        return snapshot
    }

    func makeSnapshot(_ kind: DebugFixtureKind) throws -> DebugFixtureSnapshot {
        switch kind {
        case .localOnly:
            return try localOnlySnapshot()
        case .mixedOrigin:
            return try mixedOriginSnapshot()
        }
    }

    private func localOnlySnapshot() throws -> DebugFixtureSnapshot {
        let start = try date("2026-09-28T09:50:00-04:00")
        var plan = WeeklyPlan(id: "debug-local-day", tasks: [])
        plan.tasks = [
            task("thesis", "Draft thesis chapter", estimate: 9_000),
            task("grading", "Grade assignments", estimate: 5_400),
            task("email", "Reply to coordinator", estimate: 600),
            task("research", "Explore related work", estimate: nil)
        ]
        try plan.addChild(task("thesis-outline", "Outline argument", estimate: 3_600), to: "thesis", accounting: .usesParentEstimate, recordedAt: start)
        try plan.addChild(task("thesis-figures", "Revise figures", estimate: 1_800), to: "thesis", accounting: .addsToParentEstimate, recordedAt: start)
        plan.localState.taskOrder = ["grading", "email", "thesis", "thesis-outline", "thesis-figures", "research"]
        plan.localState.deferrals = [TaskDeferral(taskID: "email", deferredAt: start, until: start.addingTimeInterval(2 * 3600))]
        plan.localState.workSegments = try workSegments(start: start)
        try plan.validate()
        return DebugFixtureSnapshot(
            startingDate: start,
            plan: plan,
            nextSourceSnapshot: nil,
            sessions: sessions(start: start),
            waterLogs: waterLogs(start: start)
        )
    }

    private func mixedOriginSnapshot() throws -> DebugFixtureSnapshot {
        guard let url = resourceBundle.url(forResource: "weekly-plan-v1", withExtension: "json") else {
            throw DebugFixtureError.missingTransferFixture
        }
        var plan = try WeeklyPlanJSON.decode(Data(contentsOf: url))
        let start = try date("2026-09-28T09:50:00-04:00")
        plan.horizon = PlanHorizon(startDay: "2026-09-28", endDayExclusive: "2026-10-12")
        plan.tasks.append(task("unbounded-research", "Investigate source gap", estimate: nil))
        try plan.addChild(task("literature-addendum", "Review newly found paper", estimate: 1_800), to: "literature-review", accounting: .addsToParentEstimate, recordedAt: start)
        plan.localState.taskOrder = ["overdue", "grading", "literature-review", "literature-x", "literature-addendum", "unbounded-research", "reading", "email"]

        var refreshedSource = plan
        refreshedSource.tasks = plan.tasks.filter { $0.sourceID != nil }
        refreshedSource.localState = PlanLocalState()
        if let index = refreshedSource.tasks.firstIndex(where: { $0.sourceID == "notion:literature-review" }) {
            refreshedSource.tasks[index].originalEstimateSeconds = 10_800
            refreshedSource.tasks[index].remainingEstimateSeconds = 7_200
        }
        try refreshedSource.validate()
        try plan.validate()
        return DebugFixtureSnapshot(
            startingDate: start,
            plan: plan,
            nextSourceSnapshot: refreshedSource,
            sessions: sessions(start: start),
            waterLogs: waterLogs(start: start)
        )
    }

    private func task(_ id: String, _ title: String, estimate: TimeInterval?) -> PlannedTask {
        PlannedTask(id: id, sourceID: nil, title: title, originalEstimateSeconds: estimate,
                    remainingEstimateSeconds: estimate, completedAt: nil, order: nil, deadline: nil,
                    prerequisiteTaskIDs: [], parentTaskID: nil, parentEstimateAccounting: nil,
                    project: nil, context: nil, minimumChunkSeconds: nil, categoryTags: [])
    }

    private func workSegments(start: Date) throws -> [TaskWorkSegment] {
        let interval = ScheduledInterval(kind: .focus, startDate: start.addingTimeInterval(-50 * 60), endDate: start.addingTimeInterval(10 * 60), isAnchored: false)
        return [
            try TaskWorkSegment(taskID: "grading", runID: UUID(), focusInterval: interval, start: interval.startDate, end: interval.startDate.addingTimeInterval(20 * 60)),
            try TaskWorkSegment(taskID: "email", runID: UUID(), focusInterval: interval, start: interval.startDate.addingTimeInterval(20 * 60), end: interval.startDate.addingTimeInterval(30 * 60)),
            try TaskWorkSegment(taskID: "grading", runID: UUID(), focusInterval: interval, start: interval.startDate.addingTimeInterval(30 * 60), end: start)
        ]
    }

    private func sessions(start: Date) -> [FocusSession] {
        [
            FocusSession(id: UUID(), startedAt: start.addingTimeInterval(-50 * 60), endedAt: start, duration: 50 * 60, completed: true),
            FocusSession(id: UUID(), startedAt: start.addingTimeInterval(3 * 24 * 3600), endedAt: start.addingTimeInterval(3 * 24 * 3600 + 40 * 60), duration: 40 * 60, completed: false),
            FocusSession(id: UUID(), startedAt: start.addingTimeInterval(13 * 24 * 3600), endedAt: start.addingTimeInterval(13 * 24 * 3600 + 50 * 60), duration: 50 * 60, completed: true)
        ]
    }

    private func waterLogs(start: Date) -> [WaterLogEntry] {
        [
            WaterLogEntry(id: UUID(), amountMl: 350, loggedAt: start.addingTimeInterval(-15 * 60)),
            WaterLogEntry(id: UUID(), amountMl: 250, loggedAt: start.addingTimeInterval(3 * 24 * 3600)),
            WaterLogEntry(id: UUID(), amountMl: 500, loggedAt: start.addingTimeInterval(13 * 24 * 3600))
        ]
    }

    private func date(_ value: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else { throw DebugFixtureError.invalidFixtureDate }
        return date
    }
}

enum DebugFixtureError: Error {
    case missingTransferFixture
    case invalidFixtureDate
}
#endif
