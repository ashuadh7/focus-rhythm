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
                if viewModel.variations.isEmpty {
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
                        Button("New rhythm", systemImage: "plus") { createAndEditVariation() }
                        Button("Duplicate", systemImage: "doc.on.doc") { viewModel.duplicateSelected() }
                        Button("Delete", systemImage: "trash", role: .destructive) { viewModel.deleteSelected() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                RhythmEditorView(viewModel: viewModel)
            }
        }
    }

    private func createAndEditVariation() {
        viewModel.createVariation()
        isEditing = true
    }

    private var variationPicker: some View {
        Section("Variation") {
            Picker("Rhythm", selection: Binding(
                get: { viewModel.selectedVariationID },
                set: { if let id = $0 { viewModel.select(id) } }
            )) {
                ForEach(viewModel.variations) { variation in
                    Text(variation.rhythm.name).tag(Optional(variation.id))
                }
            }

            if viewModel.isSelectedDefault {
                Label("Default suggestion", systemImage: "star.fill")
                    .foregroundStyle(.secondary)
            }

            Button(viewModel.isSelectedDefault ? "Remove default" : "Make default") {
                viewModel.toggleDefault()
            }
            Button("Edit variation") { isEditing = true }
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
                Stepper(
                    "Focus target: \(duration(viewModel.focusTarget))",
                    value: $viewModel.focusTarget,
                    in: 30 * 60...16 * 60 * 60,
                    step: 30 * 60
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
                Section("Name and cadence template") {
                    TextField("Variation name", text: $viewModel.draft.name)
                    timePicker(
                        "Template starts",
                        time: $viewModel.draft.dayStart,
                        onChange: viewModel.applyStandardCascade
                    )
                    timePicker(
                        "Template ends",
                        time: $viewModel.draft.dayEnd,
                        onChange: viewModel.applyStandardCascade
                    )
                    Button("Rebuild 4-hour rhythm") {
                        viewModel.applyStandardCascade()
                    }
                    Text("These template times define section and break lengths. Starting a run shifts the cadence to now.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Focus: \(Int(viewModel.draft.workDuration / 60)) min",
                        value: $viewModel.draft.workDuration,
                        in: 60...7200,
                        step: 60
                    )
                    Stepper(
                        "Short break: \(Int(viewModel.draft.shortBreakDuration / 60)) min",
                        value: $viewModel.draft.shortBreakDuration,
                        in: 60...1800,
                        step: 60
                    )
                    Picker("Final partial focus", selection: $viewModel.draft.finalPartialFocusBehavior) {
                        Text("Omit").tag(FinalPartialFocusBehavior.omit)
                        Text("Trim to fit").tag(FinalPartialFocusBehavior.trim)
                    }
                }

                Section("Work-section cadence") {
                    ForEach(viewModel.draft.workSections.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text("Section \(index + 1)").font(.headline)
                            timePicker("Starts", time: $viewModel.draft.workSections[index].startTime)
                            timePicker("Ends", time: $viewModel.draft.workSections[index].endTime)
                        }
                    }
                    .onDelete { viewModel.draft.workSections.remove(atOffsets: $0) }
                    Button("Add work section") {
                        viewModel.draft.workSections.append(WorkSection(
                            startTime: viewModel.draft.dayStart,
                            endTime: viewModel.draft.dayEnd
                        ))
                    }
                }

                Section("Long-break cadence") {
                    ForEach(viewModel.draft.longBreaks.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            TextField("Break name", text: $viewModel.draft.longBreaks[index].name)
                            timePicker("Starts", time: $viewModel.draft.longBreaks[index].startTime)
                            timePicker("Ends", time: $viewModel.draft.longBreaks[index].endTime)
                        }
                    }
                    .onDelete { viewModel.draft.longBreaks.remove(atOffsets: $0) }
                    Button("Add long break") {
                        viewModel.draft.longBreaks.append(AnchoredLongBreak(
                            name: "Long break",
                            startTime: viewModel.draft.dayStart,
                            endTime: viewModel.draft.dayEnd
                        ))
                    }
                }

                if let message = viewModel.validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit rhythm")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: viewModel.draft) { _, _ in viewModel.refreshPreview() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.discardDraftChanges()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Menu("Done") {
                        Button("Update saved variation") {
                            viewModel.saveDraftToVariation()
                            if viewModel.validationMessage == nil { dismiss() }
                        }
                        Button("Use only for this run") {
                            viewModel.refreshPreview()
                            if viewModel.validationMessage == nil { dismiss() }
                        }
                    }
                }
            }
        }
    }

    private func timePicker(
        _ title: String,
        time: Binding<TimeOfDay>,
        onChange: @escaping () -> Void = {}
    ) -> some View {
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
                    onChange()
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }
}
