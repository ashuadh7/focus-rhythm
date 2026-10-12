import SwiftUI
import Observation

/// A deliberately light planning surface. It shares the durable task catalog and
/// queue with the timer, so this view never creates a second "today" plan.
struct TodayFlowView: View {
    @State private var viewModel: TodayFlowViewModel
    @State private var isAddingTask = false

    init(clock: AppClock = AppClock()) {
        _viewModel = State(initialValue: TodayFlowViewModel(now: { clock.now }))
    }

    var body: some View {
        NavigationStack {
            List {
                if let preview = viewModel.preview {
                    overview(preview)
                    fixedCommitments(preview)
                    suggestedFlow(preview)
                    queue(preview)
                } else {
                    ContentUnavailableView("Nothing queued yet", systemImage: "checklist",
                                           description: Text("Add a task, or simply start your rhythm without planning every detail."))
                }
                if let message = viewModel.message {
                    Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add task", systemImage: "plus") { isAddingTask = true }
                }
            }
            .sheet(isPresented: $isAddingTask) {
                QuickTaskEditor { title, minutes in
                    if viewModel.addTask(title: title, minutes: minutes) { isAddingTask = false }
                }
            }
            .onAppear { viewModel.refresh() }
        }
    }

    private func overview(_ preview: TodayPreview) -> some View {
        Section("Today at a glance") {
            if preview.hasPlanningWindow {
                LabeledContent("Focus time available", value: durationText(preview.availableFocusSeconds))
                LabeledContent("Known work", value: durationText(preview.forecast.knownDemandSeconds))
                Text("Task times are suggestions. Fixed commitments stay fixed; choosing a task never changes your focus interval.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No planning window is set. Pick what matters next, or start your rhythm now—an exact day plan is optional.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func fixedCommitments(_ preview: TodayPreview) -> some View {
        if !preview.fixedCommitments.isEmpty {
            Section("Fixed commitments") {
                ForEach(preview.fixedCommitments) { item in
                    LabeledContent(item.title, value: "\(item.time.start.formatted(date: .omitted, time: .shortened))–\(item.time.end.formatted(date: .omitted, time: .shortened))")
                }
            }
        }
    }

    private func suggestedFlow(_ preview: TodayPreview) -> some View {
        Section("Suggested flow") {
            if preview.suggestedTaskIDs.isEmpty {
                Text(preview.forecast.unknownEffortTaskIDs.isEmpty
                     ? "No known task time fits in today's available window. This is a forecast, not a failure—you can still choose any eligible task."
                     : "Some work has an unknown duration. Start with an eligible task when ready; the app will keep the uncertainty visible.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(preview.forecast.placements.filter { $0.day == preview.day }) { placement in
                    if let task = viewModel.task(id: placement.taskID) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                Text("Suggested · \(durationText(placement.effortSeconds))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Choose") { viewModel.choose(task.id) }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            forecastWarnings(preview)
        }
    }

    @ViewBuilder private func forecastWarnings(_ preview: TodayPreview) -> some View {
        let conflicts = preview.forecast.conflicts
        if conflicts.contains(where: { if case .insufficientKnownCapacity = $0 { return true }; return false }) {
            Label("Known work extends beyond the available planning windows.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        if conflicts.contains(where: { if case .deadlineAtRisk = $0 { return true }; return false }) {
            Label("A deadline may be at risk. Consider choosing or moving that work earlier.", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.orange)
        }
        if !preview.forecast.unknownEffortTaskIDs.isEmpty {
            Label("Some remaining work has no estimate.", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    private func queue(_ preview: TodayPreview) -> some View {
        Section {
            ForEach(preview.queue.readyTasks) { task in
                taskRow(task, deferred: false, selected: preview.queue.selectedTaskID == task.id)
            }
            if !preview.queue.deferredTasks.isEmpty {
                Text("Not now").font(.subheadline.weight(.semibold))
                ForEach(preview.queue.deferredTasks) { task in
                    taskRow(task, deferred: true, selected: false)
                }
            }
        } header: {
            Text("Task queue")
        } footer: {
            Text("Reordering and postponing change only the durable queue. They do not promise a time slot or alter the timer.")
        }
    }

    private func taskRow(_ task: PlannedTask, deferred: Bool, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).fontWeight(selected ? .semibold : .regular)
                Text(taskDetail(task)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Choose") { viewModel.choose(task.id) }
                if !deferred { Button("Not now") { viewModel.postpone(task.id) } }
                Button("Move earlier") { viewModel.move(task.id, by: -1) }
                Button("Move later") { viewModel.move(task.id, by: 1) }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private func taskDetail(_ task: PlannedTask) -> String {
        var details = [String]()
        details.append(task.remainingEstimateSeconds.map(durationText) ?? "Time unknown")
        if let parent = task.parentTaskID.flatMap({ viewModel.task(id: $0)?.title }) { details.append("Part of \(parent)") }
        if let deadline = task.deadline { details.append("Due \(deadline.formatted(date: .abbreviated, time: .omitted))") }
        return details.joined(separator: " · ")
    }
}

@Observable
final class TodayFlowViewModel {
    private let store: WeeklyPlanStoring
    private let now: () -> Date
    private(set) var plan: WeeklyPlan?
    private(set) var preview: TodayPreview?
    private(set) var message: String?

    init(store: WeeklyPlanStoring = UserDefaultsWeeklyPlanStore(), now: @escaping () -> Date = Date.init) {
        self.store = store; self.now = now; refresh()
    }

    func refresh() { plan = store.load(); preview = plan?.todayPreview(at: now()) }
    func task(id: String) -> PlannedTask? { plan?.tasks.first { $0.id == id } }

    @discardableResult func addTask(title: String, minutes: Double?) -> Bool {
        update { plan in _ = try plan.addLocalTask(title: title, estimateSeconds: minutes.map { $0 * 60 }, recordedAt: now()) }
    }
    func choose(_ id: String) { _ = update { try $0.selectTask(id) } }
    func postpone(_ id: String) { _ = update { try $0.deferTask(id, at: now()) } }
    func move(_ id: String, by offset: Int) {
        _ = update { plan in
            var ids = plan.localState.taskOrder ?? plan.tasks.map(\.id)
            guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
            ids.swapAt(index, index + offset); try plan.reorderTasks(ids)
        }
    }

    @discardableResult private func update(_ body: (inout WeeklyPlan) throws -> Void) -> Bool {
        do {
            var candidate = store.load() ?? WeeklyPlan(id: UUID().uuidString, tasks: [])
            try body(&candidate); try store.save(candidate); message = nil; refresh(); return true
        } catch { message = error.localizedDescription; return false }
    }
}

private struct QuickTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var minutes = ""
    let save: (String, Double?) -> Void
    var body: some View {
        NavigationStack { Form {
            TextField("What needs doing?", text: $title)
            TextField("Estimated minutes (optional)", text: $minutes).keyboardType(.decimalPad)
        }.navigationTitle("New task").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add") { save(title, Double(minutes)) }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }}
    }
}

private func durationText(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
}
