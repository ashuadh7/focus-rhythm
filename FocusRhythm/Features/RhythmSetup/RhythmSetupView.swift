import SwiftUI

struct RhythmSetupView: View {
    @State private var viewModel = RhythmSetupViewModel()
    @State private var isEditing = false
    @State private var startedRun: ActiveRhythmRun?
    @State private var planningDate = Date()
    let onStart: (ActiveRhythmRun) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.variations.isEmpty {
                    ContentUnavailableView(
                        "No rhythms yet",
                        systemImage: "clock.badge.plus",
                        description: Text("Create a reusable rhythm for the shape of your day.")
                    )
                    Button("Create rhythm") { createAndEditVariation() }
                } else {
                    variationPicker
                    preview
                    actions
                }
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

            if viewModel.isSelectedForToday {
                Label("Planned for today", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
            } else if viewModel.isSelectedDefault {
                Label("Default suggestion", systemImage: "star.fill")
                    .foregroundStyle(.secondary)
            }

            Button("Choose for today") { viewModel.selectForToday() }
            DatePicker("Plan another date", selection: $planningDate, displayedComponents: .date)
            Button("Choose for \(planningDate.formatted(date: .abbreviated, time: .omitted))") {
                if let id = viewModel.selectedVariationID {
                    viewModel.plan(id, for: planningDate)
                }
            }
            Button(viewModel.isSelectedDefault ? "Remove default" : "Make default") {
                viewModel.toggleDefault()
            }
            Button("Edit variation") { isEditing = true }
        }
    }

    @ViewBuilder
    private var preview: some View {
        Section("Preview") {
            if let schedule = viewModel.preview {
                LabeledContent("Name", value: schedule.rhythmName)
                LabeledContent("Day") {
                    Text("\(schedule.dayStart.formatted(date: .omitted, time: .shortened))–\(schedule.dayEnd.formatted(date: .omitted, time: .shortened))")
                }
                LabeledContent("Expected focus", value: duration(schedule.expectedFocusTime))
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

            Text("Starts from the current time, keeps future fixed breaks and today’s end time, and saves an independent run snapshot.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                Section("Name and timing") {
                    TextField("Variation name", text: $viewModel.draft.name)
                    timePicker(
                        "Day starts",
                        time: $viewModel.draft.dayStart,
                        onChange: viewModel.applyStandardCascade
                    )
                    timePicker(
                        "Day ends",
                        time: $viewModel.draft.dayEnd,
                        onChange: viewModel.applyStandardCascade
                    )
                    Button("Rebuild 4-hour rhythm") {
                        viewModel.applyStandardCascade()
                    }
                    Text("Builds four-hour work sections from the day start, with one-hour long breaks between them. You can edit every generated time below.")
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

                Section("Work sections") {
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

                Section("Anchored long breaks") {
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
