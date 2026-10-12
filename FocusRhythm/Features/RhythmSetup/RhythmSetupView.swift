import SwiftUI

struct RhythmSetupView: View {
    @State private var viewModel: RhythmSetupViewModel
    @State private var isEditing = false
    @State private var isCreatingTask = false
    @State private var editingTask: PlannedTask?
    @State private var startedRun: ActiveRhythmRun?
    let onStart: (ActiveRhythmRun) -> Void

    init(clock: AppClock = AppClock(), onStart: @escaping (ActiveRhythmRun) -> Void) {
        _viewModel = State(initialValue: RhythmSetupViewModel(now: { clock.now }))
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.variations.isEmpty && !viewModel.isUsingOneTimeRhythm {
                    ContentUnavailableView(
                        "No rhythms yet",
                        systemImage: "clock",
                        description: Text("Create a reusable rhythm for the shape of your day.")
                    )
                    Button("Create rhythm") { createAndEditVariation() }
                    taskQueue
                } else {
                    variationPicker
                    taskQueue
                    endCondition
                    preview
                    actions
                }
                manualTestAction
            }
            .navigationTitle("Choose today’s rhythm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Duplicate", systemImage: "doc.on.doc") { viewModel.duplicateSelected() }
                            .disabled(viewModel.selectedVariationID == nil)
                        Button("Delete", systemImage: "trash", role: .destructive) { viewModel.deleteSelected() }
                            .disabled(viewModel.selectedVariationID == nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isEditing, onDismiss: viewModel.cancelDraftEditing) {
                RhythmEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: $isCreatingTask) {
                LocalTaskEditor(task: nil, possibleParents: viewModel.possibleParents()) { title, estimate, deadline, project, context, tags, parentID, accounting in
                    if viewModel.createLocalTask(title: title, estimateSeconds: estimate, deadline: deadline, project: project, context: context, categoryTags: tags, parentID: parentID, accounting: accounting) {
                        isCreatingTask = false
                    }
                }
            }
            .sheet(item: $editingTask) { task in
                LocalTaskEditor(task: task, possibleParents: viewModel.possibleParents(for: task.id)) { title, estimate, deadline, project, context, tags, parentID, accounting in
                    if viewModel.editLocalTask(task.id, title: title, estimateSeconds: estimate, deadline: deadline, project: project, context: context, categoryTags: tags, parentID: parentID, accounting: accounting) {
                        editingTask = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var taskQueue: some View {
        Section {
            Button("Add task", systemImage: "plus") { isCreatingTask = true }
            if let queue = viewModel.taskQueue, !queue.selectableTasks.isEmpty {
                if let suggested = queue.suggestedTask {
                    Text("Suggested next: \(suggested.title)")
                        .font(.subheadline.weight(.semibold))
                }

                ForEach(queue.readyTasks) { task in
                    queueRow(task, isDeferred: false, queue: queue)
                }

                if !queue.deferredTasks.isEmpty {
                    Text("Not now")
                        .font(.subheadline.weight(.semibold))
                    ForEach(queue.deferredTasks) { task in
                        queueRow(task, isDeferred: true, queue: queue)
                    }
                    if let returnDate = queue.nextDeferredReturn {
                        Text("Postponed work returns at \(returnDate.formatted(date: .omitted, time: .shortened)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

            }
            if let message = viewModel.taskQueueMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Task queue")
        } footer: {
            Text("Add a task any time. Choose a task for your next focus block, change its priority, or postpone it briefly. Postponing is not completion.")
        }
    }

    private func queueRow(_ task: PlannedTask, isDeferred: Bool, queue: TaskQueue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body.weight(queue.selectedTaskID == task.id ? .semibold : .regular))
                if let project = task.project {
                    Text(project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if task.hasUnknownEstimate {
                    Text("Time unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let parentID = task.parentTaskID,
                   let parent = viewModel.possibleParents().first(where: { $0.id == parentID }) {
                    Text("Part of \(parent.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if queue.returnedForDeadline.contains(task.id) {
                    Text("Returned because its deadline needs attention")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Menu {
                Button("Choose") { viewModel.selectQueuedTask(task.id) }
                if viewModel.hasActiveDescendants(task) {
                    Button("Mark parent and children done") { viewModel.completeQueuedTask(task.id, includingDescendants: true) }
                } else {
                    Button("Mark done") { viewModel.completeQueuedTask(task.id) }
                }
                if !isDeferred {
                    Button("Not now") { viewModel.postponeQueuedTask(task.id) }
                }
                Button("Move earlier") { viewModel.moveQueuedTask(task.id, by: -1) }
                Button("Move later") { viewModel.moveQueuedTask(task.id, by: 1) }
                if task.sourceID == nil {
                    Button("Edit task") { editingTask = task }
                    if viewModel.hasActiveDescendants(task) {
                        Button("Abandon parent and children", role: .destructive) { viewModel.abandonLocalTaskAndDescendants(task.id) }
                    } else {
                        Button("Abandon task", role: .destructive) { viewModel.abandonLocalTask(task.id) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Options for \(task.title)")
        }
    }

    private func createAndEditVariation() {
        viewModel.beginCreatingVariation()
        isEditing = true
    }

    private var variationPicker: some View {
        Section("Variation") {
            Picker("Rhythm", selection: Binding(
                get: { viewModel.selectedVariationID },
                set: { if let id = $0 { viewModel.select(id) } }
            )) {
                if viewModel.selectedVariationID == nil {
                    Text("One-time rhythm").tag(Optional<UUID>.none)
                }
                ForEach(viewModel.variations) { variation in
                    Text(variation.rhythm.name).tag(Optional(variation.id))
                }
            }

            Button("New variation", systemImage: "plus") { createAndEditVariation() }

            if viewModel.isSelectedDefault {
                Label("Default suggestion", systemImage: "star.fill")
                    .foregroundStyle(.secondary)
            }

            Button(viewModel.isSelectedDefault ? "Remove default" : "Make default") {
                viewModel.toggleDefault()
            }
            .disabled(viewModel.selectedVariationID == nil)
            Button("Edit variation") {
                viewModel.beginEditingSelected()
                isEditing = true
            }
            .disabled(viewModel.selectedVariationID == nil)
        }
    }

    private var endCondition: some View {
        Section("Start now") {
            Picker("End condition", selection: $viewModel.runEndMode) {
                Text("Stop at").tag(RunEndMode.stopAt)
                Text("Focus for").tag(RunEndMode.focusFor)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.runEndMode) { _, _ in viewModel.refreshRunPreview() }

            switch viewModel.runEndMode {
            case .stopAt:
                timePicker("Stop at", time: $viewModel.stopAt)
            case .focusFor:
                HourMinuteWheelPicker(
                    title: "Focus target",
                    duration: $viewModel.focusTarget
                )
                .onChange(of: viewModel.focusTarget) { _, _ in viewModel.refreshRunPreview() }
                Text("Focus time excludes short and long breaks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        Section("Preview") {
            if let schedule = viewModel.runPreview {
                LabeledContent("Name", value: schedule.rhythmName)
                LabeledContent("Starts", value: "Now")
                LabeledContent("Estimated finish") {
                    Text(schedule.dayEnd.formatted(date: .omitted, time: .shortened))
                }
                LabeledContent("Focus", value: duration(schedule.expectedFocusTime))
                LabeledContent("Breaks", value: duration(
                    schedule.dayEnd.timeIntervalSince(schedule.dayStart) - schedule.expectedFocusTime
                ))
                LabeledContent("Sessions", value: "\(schedule.focusSessionCount)")
                if schedule.longBreakDetails.isEmpty {
                    LabeledContent("Long breaks", value: "None")
                } else {
                    ForEach(Array(schedule.longBreakDetails.enumerated()), id: \.offset) { _, item in
                        LabeledContent(item.name) {
                            Text("\(item.startDate.formatted(date: .omitted, time: .shortened))–\(item.endDate.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                }
            } else if let message = viewModel.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var actions: some View {
        Section {
            Button {
                if let run = viewModel.startNow() {
                    startedRun = run
                    onStart(run)
                }
            } label: {
                Text("Start now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStart)

            Text("Starts immediately. The selected rhythm controls the cadence; your end condition controls when the run finishes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var manualTestAction: some View {
        Section("Manual testing") {
            Button("Start test") {
                let run = viewModel.startManualTest()
                startedRun = run
                onStart(run)
            }
            Text("Runs five named 20-second focus blocks with 10-second breaks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func timePicker(_ title: String, time: Binding<TimeOfDay>) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: {
                    Calendar.current.date(from: DateComponents(
                        year: 2001,
                        month: 1,
                        day: 1,
                        hour: time.wrappedValue.hour,
                        minute: time.wrappedValue.minute
                    )) ?? Date()
                },
                set: {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                    time.wrappedValue = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
                    viewModel.refreshRunPreview()
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }
}

private struct LocalTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var estimateMinutes: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var project: String
    @State private var context: String
    @State private var tags: String
    @State private var parentID: String?
    @State private var accounting: ChildEstimateAccounting
    private let isEditing: Bool
    private let possibleParents: [PlannedTask]
    let save: (String, TimeInterval?, Date?, String?, String?, [String], String?, ChildEstimateAccounting?) -> Void

    init(task: PlannedTask?, possibleParents: [PlannedTask], save: @escaping (String, TimeInterval?, Date?, String?, String?, [String], String?, ChildEstimateAccounting?) -> Void) {
        _title = State(initialValue: task?.title ?? "")
        _estimateMinutes = State(initialValue: task?.remainingEstimateSeconds.map { String(Int($0 / 60)) } ?? "")
        _hasDeadline = State(initialValue: task?.deadline != nil)
        _deadline = State(initialValue: task?.deadline ?? Date())
        _project = State(initialValue: task?.project ?? "")
        _context = State(initialValue: task?.context ?? "")
        _tags = State(initialValue: task?.categoryTags.joined(separator: ", ") ?? "")
        _parentID = State(initialValue: task?.parentTaskID)
        _accounting = State(initialValue: task?.parentEstimateAccounting ?? .usesParentEstimate)
        isEditing = task != nil
        self.possibleParents = possibleParents
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What needs doing?", text: $title)
                TextField("Estimated minutes (optional)", text: $estimateMinutes)
                    .keyboardType(.numberPad)
                Toggle("Deadline", isOn: $hasDeadline)
                if hasDeadline { DatePicker("Due", selection: $deadline) }
                TextField("Project (optional)", text: $project)
                TextField("Context (optional)", text: $context)
                TextField("Tags, separated by commas", text: $tags)
                Section("Break down work") {
                    Picker("Parent task", selection: $parentID) {
                        Text("No parent").tag(Optional<String>.none)
                        ForEach(possibleParents) { parent in
                            Text(parentLabel(parent)).tag(Optional(parent.id))
                        }
                    }
                    if let parentID, let parent = possibleParents.first(where: { $0.id == parentID }) {
                        Picker("How should this affect the estimate?", selection: $accounting) {
                            Text("Use existing estimate").tag(ChildEstimateAccounting.usesParentEstimate)
                            Text("Add to estimate").tag(ChildEstimateAccounting.addsToParentEstimate)
                        }
                        .pickerStyle(.navigationLink)
                        Text(accountingExplanation(for: parent))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit task" : "New task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        let minutes = Double(estimateMinutes.trimmingCharacters(in: .whitespacesAndNewlines))
                        save(title, minutes.map { $0 * 60 }, hasDeadline ? deadline : nil,
                             project.isEmpty ? nil : project, context.isEmpty ? nil : context,
                             tags.split(separator: ",").map(String.init), parentID,
                             parentID == nil ? nil : accounting)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func parentLabel(_ parent: PlannedTask) -> String {
        let breadcrumb = parent.parentTaskID.flatMap { id in possibleParents.first(where: { $0.id == id })?.title }
        return breadcrumb.map { "\($0) › \(parent.title)" } ?? parent.title
    }

    private func accountingExplanation(for parent: PlannedTask) -> String {
        guard let minutes = Double(estimateMinutes.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return parent.remainingEstimateSeconds == nil
                ? "The parent has no estimate, so the total stays unknown until you estimate it."
                : "Add an estimate to see exactly how this child changes the known work."
        }
        let amount = Int(minutes)
        if parent.remainingEstimateSeconds == nil {
            return "The parent has no estimate, so the total remains unknown. This relationship is still recorded."
        }
        switch accounting {
        case .usesParentEstimate:
            return "This uses \(amount) minutes already included in \(parent.title)'s remaining work."
        case .addsToParentEstimate:
            return "This adds \(amount) minutes of newly discovered work on top of \(parent.title)'s remaining work."
        }
    }
}

private struct RhythmEditorView: View {
    @Bindable var viewModel: RhythmSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Variation") {
                    TextField("Variation name", text: $viewModel.draft.name)
                }

                Section("Focus") {
                    MinuteWheelPicker(
                        title: "Focus time",
                        duration: $viewModel.draft.workDuration,
                        minuteValues: Array(stride(from: 5, through: 120, by: 5))
                    )
                }

                Section("Breaks") {
                    MinuteWheelPicker(
                        title: "Short break time",
                        duration: $viewModel.draft.shortBreakDuration,
                        minuteValues: Array(1...30)
                    )
                    MinuteWheelPicker(
                        title: "Long break time",
                        duration: $viewModel.draft.longBreakDuration,
                        minuteValues: Array(stride(from: 5, through: 120, by: 5))
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Focus sessions before long break")
                        Picker(
                            "Focus sessions before long break",
                            selection: $viewModel.draft.sessionsBeforeLongBreak
                        ) {
                            ForEach(1...12, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 120)
                        .clipped()
                    }
                }

                if let message = viewModel.validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.isCreatingVariation ? "New variation" : "Edit variation")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: viewModel.draft) { _, _ in viewModel.refreshPreview() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelDraftEditing()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Menu("Done") {
                        Button(viewModel.isCreatingVariation ? "Save variation" : "Update saved variation") {
                            if viewModel.saveEditingDraft() { dismiss() }
                        }
                        Button("Use only for this run") {
                            if viewModel.useEditingDraftForThisRun() { dismiss() }
                        }
                    }
                }
            }
        }
    }

}

private struct HourMinuteWheelPicker: View {
    let title: String
    @Binding var duration: TimeInterval

    private let hourValues = Array(0...23)
    private let minuteValues = [0, 15, 30, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            HStack(spacing: 0) {
                Picker("Hours", selection: hourSelection) {
                    ForEach(hourValues, id: \.self) { hours in
                        Text(hours == 1 ? "1 hour" : "\(hours) hours").tag(hours)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()

                Picker("Minutes", selection: minuteSelection) {
                    ForEach(minuteValues, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 120)
            .clipped()
        }
    }

    private var hourSelection: Binding<Int> {
        Binding(
            get: { normalizedDurationComponents.hours },
            set: { setDuration(hours: $0, minutes: normalizedDurationComponents.minutes) }
        )
    }

    private var minuteSelection: Binding<Int> {
        Binding(
            get: { normalizedDurationComponents.minutes },
            set: { setDuration(hours: normalizedDurationComponents.hours, minutes: $0) }
        )
    }

    private var normalizedDurationComponents: (hours: Int, minutes: Int) {
        let totalMinutes = max(15, Int((duration / 60).rounded()))
        let roundedToQuarterHour = Int((Double(totalMinutes) / 15).rounded()) * 15
        let clampedMinutes = min(roundedToQuarterHour, 23 * 60 + 45)
        return (clampedMinutes / 60, clampedMinutes % 60)
    }

    private func setDuration(hours: Int, minutes: Int) {
        duration = TimeInterval(max(15, hours * 60 + minutes) * 60)
    }
}

private struct MinuteWheelPicker: View {
    let title: String
    @Binding var duration: TimeInterval
    let minuteValues: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Picker(
                title,
                selection: Binding(
                    get: { Int(duration / 60) },
                    set: { duration = TimeInterval($0 * 60) }
                )
            ) {
                ForEach(minuteValues, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 120)
            .clipped()
        }
    }
}
