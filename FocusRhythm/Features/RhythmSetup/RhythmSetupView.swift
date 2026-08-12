import SwiftUI

struct RhythmSetupView: View {
    @State private var viewModel: RhythmSetupViewModel
    @State private var isEditing = false
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
                } else {
                    variationPicker
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
