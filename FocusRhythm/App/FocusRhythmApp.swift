import SwiftUI

@main
struct FocusRhythmApp: App {
    var body: some Scene {
        WindowGroup {
            AppEntryView()
        }
    }
}

private struct AppEntryView: View {
    @State private var clock: AppClock
    @State private var activeRun: ActiveRhythmRun?
    @State private var stoppedRun: StoppedRhythmRun?
#if DEBUG
    @State private var pendingFixture: DebugFixtureKind?
#endif

    private let activeRunStore = UserDefaultsActiveRunStore()
    private let stoppedRunStore = UserDefaultsStoppedRunStore()
    private let runHistoryStore = UserDefaultsRunHistoryStore()

    init() {
        let clock = AppClock()
        _clock = State(initialValue: clock)
        _activeRun = State(initialValue: ActiveRunRestorer(now: { clock.now }).restore())
        _stoppedRun = State(initialValue: UserDefaultsStoppedRunStore().load())
    }

    @ViewBuilder
    var body: some View {
#if DEBUG
        content
            .safeAreaInset(edge: .bottom) {
                debugClockControls
            }
            .confirmationDialog(
                "Replace saved data with a debug fixture?",
                isPresented: Binding(
                    get: { pendingFixture != nil },
                    set: { if !$0 { pendingFixture = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Replace with \(pendingFixture?.title ?? "fixture")", role: .destructive) {
                    loadPendingFixture()
                }
                Button("Cancel", role: .cancel) {
                    pendingFixture = nil
                }
            } message: {
                Text("This replaces the saved task catalog, focus sessions, water logs, and any active or stopped run. It is available only in debug builds.")
            }
#else
        content
#endif
    }

    @ViewBuilder
    private var content: some View {
        TabView {
            focusSurface
                .tabItem { Label("Focus", systemImage: "timer") }
            TasksWorkspaceView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
        }
    }

    @ViewBuilder
    private var focusSurface: some View {
        if let activeRun {
            TimerHomeView(
                run: activeRun,
                clock: clock,
                onEndDay: {
                    self.activeRun = nil
                    self.stoppedRun = stoppedRunStore.load()
                }
            )
        } else if let stoppedRun {
            StoppedRunReviewView(
                run: stoppedRun,
                onContinue: continueRun,
                onDiscard: discardRun
            )
        } else {
            RhythmSetupView(clock: clock) { run in
                activeRun = run
            }
        }
    }

    private func continueRun(_ itemIDs: Set<UUID>) {
        guard let stoppedRun,
              let run = stoppedRun.continuedRun(using: itemIDs, at: clock.now)
        else { return }
        activeRunStore.save(run)
        stoppedRunStore.clear()
        self.stoppedRun = nil
        activeRun = run
    }

    private func discardRun() {
        guard var sourceRun = stoppedRun?.sourceRun else { return }
        sourceRun.status = .ended
        activeRunStore.save(sourceRun)
        runHistoryStore.record(CompletedRhythmRun(
            id: sourceRun.id,
            startedAt: sourceRun.startedAt,
            schedule: sourceRun.schedule,
            outcome: .endedEarly,
            adjustments: sourceRun.adjustments
        ))
        activeRunStore.clear()
        stoppedRunStore.clear()
        stoppedRun = nil
    }

#if DEBUG
    private var debugClockControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Clock")
                    .font(.caption.weight(.semibold))
                Picker("Clock rate", selection: Binding(
                    get: { clock.rate },
                    set: { clock.setRate($0) }
                )) {
                    ForEach(AppClock.availableRates, id: \.self) { rate in
                        Text("\(Int(rate))×").tag(rate)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                Button("‹ Day") { clock.travel(days: -1) }
                Text(clock.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: .infinity)
                Button("Day ›") { clock.travel(days: 1) }
                Button("Today") { clock.returnToWallClock() }
            }
            .buttonStyle(.bordered)

            Menu("Load debug fixture") {
                ForEach(DebugFixtureKind.allCases) { fixture in
                    Button(fixture.title) { pendingFixture = fixture }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func loadPendingFixture() {
        guard let pendingFixture else { return }
        defer { self.pendingFixture = nil }
        do {
            let fixture = try DebugFixtureLoader().load(pendingFixture)
            activeRun = nil
            stoppedRun = nil
            clock.setDate(fixture.startingDate)
        } catch {
            assertionFailure("Unable to load debug fixture: \(error)")
        }
    }
#endif
}

/// Planning lives on its own tab so the Focus surface can stay deliberately small.
private struct TasksWorkspaceView: View {
    @State private var plan: WeeklyPlan?
    @State private var editingTask: PlannedTask?
    @State private var isAddingTask = false
    @State private var message: String?
    private let store: WeeklyPlanStoring

    init(store: WeeklyPlanStoring = UserDefaultsWeeklyPlanStore()) {
        self.store = store
        _plan = State(initialValue: store.load())
    }

    var body: some View {
        NavigationStack {
            List {
                if let plan, !plan.tasks.isEmpty {
                    ForEach(EisenhowerQuadrant.allCases) { quadrant in
                        let tasks = plan.tasks.filter { classification(for: $0).quadrant == quadrant }
                        Section(quadrant.title) {
                            if tasks.isEmpty {
                                Text("No tasks").foregroundStyle(.secondary)
                            }
                            ForEach(tasks) { task in
                                Button { editingTask = task } label: { taskRow(task) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if !plan.localState.carryoverTaskIDs.isEmpty {
                        Section("Carryover") {
                            Text("Carryover remains separate from the active queue until you deliberately bring it back.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No tasks yet", systemImage: "checklist",
                        description: Text("Add work here. Focus will select only eligible tasks when a run starts.")
                    )
                }
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add task", systemImage: "plus") { isAddingTask = true }
                }
            }
            .onAppear { reload() }
            .sheet(isPresented: $isAddingTask) {
                TaskPlanningEditor(task: nil, classification: .default) { title, estimate, classification in
                    addTask(title: title, estimate: estimate, classification: classification)
                }
            }
            .sheet(item: $editingTask) { task in
                TaskPlanningEditor(task: task, classification: classification(for: task)) { title, estimate, classification in
                    update(task: task, title: title, estimate: estimate, classification: classification)
                }
            }
        }
    }

    private func classification(for task: PlannedTask) -> TaskClassification {
        plan?.localState.classifications[task.id] ?? .default
    }

    private func taskRow(_ task: PlannedTask) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.title).font(.body.weight(.medium))
            Text(details(for: task)).font(.caption).foregroundStyle(.secondary)
            if let parentID = task.parentTaskID,
               let parent = plan?.tasks.first(where: { $0.id == parentID }) {
                Text("Part of \(parent.title)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func details(for task: PlannedTask) -> String {
        let classification = classification(for: task)
        var values = [classification.workKind.title, classification.planningState.title]
        values.append(task.remainingEstimateSeconds.map(duration) ?? "Time unknown")
        if let deadline = task.deadline { values.append("Due \(deadline.formatted(date: .abbreviated, time: .omitted))") }
        if classification.planningState == .conditionalTask && !classification.isConditionReady {
            values.append("Waiting")
        }
        return values.joined(separator: " · ")
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func addTask(title: String, estimate: TimeInterval?, classification: TaskClassification) {
        do {
            var updated = plan ?? WeeklyPlan(id: UUID().uuidString, tasks: [])
            let id = try updated.addLocalTask(title: title, estimateSeconds: estimate)
            try updated.setClassification(classification, for: id)
            try store.save(updated)
            plan = updated
            isAddingTask = false
        } catch { message = error.localizedDescription }
    }

    private func update(task: PlannedTask, title: String, estimate: TimeInterval?, classification: TaskClassification) {
        do {
            guard var updated = plan else { return }
            if task.sourceID == nil {
                try updated.editLocalTask(task.id, title: title, estimateSeconds: estimate,
                                          deadline: task.deadline, project: task.project,
                                          context: task.context, categoryTags: task.categoryTags,
                                          parentID: task.parentTaskID, accounting: task.parentEstimateAccounting)
            }
            try updated.setClassification(classification, for: task.id)
            try store.save(updated)
            plan = updated
            editingTask = nil
        } catch { message = error.localizedDescription }
    }

    private func reload() { plan = store.load() }
}

private struct TaskPlanningEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var minutes: String
    @State private var classification: TaskClassification
    private let isLocalTask: Bool
    let save: (String, TimeInterval?, TaskClassification) -> Void

    init(task: PlannedTask?, classification: TaskClassification,
         save: @escaping (String, TimeInterval?, TaskClassification) -> Void) {
        _title = State(initialValue: task?.title ?? "")
        _minutes = State(initialValue: task?.remainingEstimateSeconds.map { String(Int($0 / 60)) } ?? "")
        _classification = State(initialValue: classification)
        isLocalTask = task?.sourceID == nil
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLocalTask {
                    TextField("What needs doing?", text: $title)
                    TextField("Estimated minutes (optional)", text: $minutes).keyboardType(.numberPad)
                } else {
                    LabeledContent("Imported task", value: title)
                    Text("Source-owned task details stay intact; classification is your local planning choice.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Classify") {
                    Picker("Eisenhower quadrant", selection: $classification.quadrant) {
                        ForEach(EisenhowerQuadrant.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Work kind", selection: $classification.workKind) {
                        ForEach(TaskWorkKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Planning state", selection: $classification.planningState) {
                        ForEach(TaskPlanningState.allCases) { Text($0.title).tag($0) }
                    }
                    if classification.planningState == .conditionalTask {
                        Toggle("Condition is ready", isOn: $classification.isConditionReady)
                    }
                }
            }
            .navigationTitle("Task details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(title, Double(minutes.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 * 60 }, classification)
                    }.disabled(isLocalTask && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct StoppedRunReviewView: View {
    let run: StoppedRhythmRun
    let onContinue: (Set<UUID>) -> Void
    let onDiscard: () -> Void

    @State private var includedItemIDs: Set<UUID>
    @State private var isConfirmingDiscard = false

    init(
        run: StoppedRhythmRun,
        onContinue: @escaping (Set<UUID>) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.run = run
        self.onContinue = onContinue
        self.onDiscard = onDiscard
        _includedItemIDs = State(initialValue: Set(run.remainingPlan.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Stopped day") {
                    LabeledContent("Focus completed", value: durationText(run.completedFocusTime))
                    LabeledContent("Completed intervals", value: "\(run.completedFocusIntervals)")
                    LabeledContent("Original target", value: durationText(run.originalFocusTarget))
                    LabeledContent("Focus remaining", value: durationText(selectedFocusTime))
                    Text("Stopped \(run.stoppedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(run.remainingPlan) { item in
                        Toggle(isOn: Binding(
                            get: { includedItemIDs.contains(item.id) },
                            set: { included in
                                if included { includedItemIDs.insert(item.id) }
                                else { includedItemIDs.remove(item.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.label ?? title(for: item.kind))
                                Text("\(title(for: item.kind)) · \(durationText(item.duration))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Remaining plan")
                } footer: {
                    Text("Turn off blocks to revise the remainder before continuing. Task identities can be attached here when planning is added.")
                }

                Section {
                    Button("Continue remaining plan") {
                        onContinue(includedItemIDs)
                    }
                    .disabled(selectedFocusTime <= 0)

                    Button("Discard remaining plan", role: .destructive) {
                        isConfirmingDiscard = true
                    }
                }
            }
            .navigationTitle("Review unfinished day")
            .confirmationDialog(
                "Discard the remaining plan?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard plan", role: .destructive, action: onDiscard)
                Button("Keep it", role: .cancel) {}
            }
        }
    }

    private var selectedFocusTime: TimeInterval {
        run.remainingPlan
            .filter { includedItemIDs.contains($0.id) && $0.kind == .focus }
            .reduce(0) { $0 + $1.duration }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if totalMinutes >= 60 { return "\(totalMinutes / 60)h \(totalMinutes % 60)m" }
        if totalMinutes > 0 { return "\(totalMinutes)m" }
        return "\(seconds)s"
    }

    private func title(for kind: ScheduledIntervalKind) -> String {
        switch kind {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case let .longBreak(name): return name
        }
    }
}
