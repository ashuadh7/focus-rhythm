import SwiftUI

struct TimerHomeView: View {
    @State private var viewModel: FocusTimerViewModel
    @State private var waterLoggingViewModel: WaterLoggingViewModel
    @State private var isShowingSummary = false
    @State private var isShowingTodayFlow = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var pickerDuration: TimeInterval = FocusTimerViewModel.defaultBreakDuration
    @State private var endCycleReasoning = ""
    @Environment(\.scenePhase) private var scenePhase
    private let onEndDay: () -> Void
    private let clock: AppClock

    private static let workHoldDuration: TimeInterval = 5
    private static let breakHoldDuration: TimeInterval = 1
    private static let holdTickInterval: TimeInterval = 0.05

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(
        workDuration: TimeInterval? = nil,
        breakDuration: TimeInterval? = nil,
        clock: AppClock = AppClock(),
        onEndDay: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: FocusTimerViewModel(
            workDuration: workDuration,
            breakDuration: breakDuration,
            now: { clock.now }
        ))
        _waterLoggingViewModel = State(initialValue: WaterLoggingViewModel(now: { clock.now }))
        self.clock = clock
        self.onEndDay = onEndDay
    }

    init(
        run: ActiveRhythmRun,
        activeRunStore: ActiveRunStoring = UserDefaultsActiveRunStore(),
        clock: AppClock = AppClock(),
        onEndDay: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: FocusTimerViewModel(
            run: run,
            activeRunStore: activeRunStore,
            now: { clock.now }
        ))
        _waterLoggingViewModel = State(initialValue: WaterLoggingViewModel(now: { clock.now }))
        self.clock = clock
        self.onEndDay = onEndDay
    }

    var body: some View {
        content
            .sheet(isPresented: $isShowingSummary) {
                DailySummaryView(now: { clock.now })
            }
            .sheet(isPresented: $isShowingTodayFlow) {
                TodayFlowView(clock: clock)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isSelectingBreakDuration },
                set: { if !$0 { viewModel.cancelBreakSelection() } }
            )) {
                breakDurationPicker
            }
            .sheet(isPresented: Binding(
                get: { viewModel.isEndingCycle },
                set: { if !$0 { viewModel.cancelEndCycle() } }
            )) {
                endCycleSheet
            }
            .task {
                viewModel.requestNotificationPermission()
                if viewModel.phase == .completedDay {
                    isShowingSummary = true
                }
            }
            .onChange(of: viewModel.phase) { _, phase in
                if phase == .completedDay {
                    isShowingSummary = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.refreshForForeground()
                }
            }
    }

    private var content: some View {
        VStack(spacing: 32) {
            HStack {
                Spacer()
                Button("Today") { isShowingTodayFlow = true }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

#if DEBUG
            if clock.rate != 1 {
                Text("Running at \(Int(clock.rate))×")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Clock speed \(Int(clock.rate)) times")
            }
#endif

            Spacer()

            VStack(spacing: 12) {
                if let blockName = viewModel.currentBlockName {
                    Text(blockName)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }

                Text(viewModel.phaseTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.remainingTimeText)
                    .font(.system(size: 84, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel(accessibilityTimeLabel)

                if viewModel.phase == .work {
                    currentTaskCard
                }

                if let next = viewModel.nextTransition {
                    Text("Next: \(next.title) at \(next.date.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let dayEnd = viewModel.dayEnd {
                    Text("Day ends \(dayEnd.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.scheduleChangeMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if viewModel.isBonusLowTimeWarningVisible {
                    Text("Bonus time almost up")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                } else if viewModel.isLowTimeWarningVisible {
                    Text("Running low")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }

                if let warningMessage = viewModel.longBreakWarningMessage {
                    Text(warningMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if viewModel.phase == .break || viewModel.phase == .shortBreak {
                    WaterPromptView(viewModel: waterLoggingViewModel)
                } else {
                    Text(viewModel.prompt)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            if viewModel.phase != .completedDay {
                primaryControl
            } else {
                Button("Return to setup", action: onEndDay)
                    .buttonStyle(.borderedProminent)
            }

            if viewModel.isAddTimeAvailable {
                Button("Add time") { viewModel.addTime() }
                    .font(.subheadline.weight(.medium))
            }

            if viewModel.phase == .idle, viewModel.dayEnd == nil {
                Button("Set up today’s rhythm", action: onEndDay)
                    .font(.subheadline.weight(.medium))
            } else if viewModel.phase == .idle {
                Button("Return to setup", action: onEndDay)
                    .font(.subheadline.weight(.medium))
            } else if viewModel.phase.isRunning {
                Button("End for today") {
                    endCycleReasoning = ""
                    viewModel.requestEndCycle()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .onReceive(ticker) { _ in
            viewModel.refreshForClockTick()
        }
    }

    @ViewBuilder
    private var currentTaskCard: some View {
        if let task = viewModel.currentTask {
            VStack(alignment: .leading, spacing: 6) {
                Text("Working on")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let parent = task.parentTitle {
                    Label(parent, systemImage: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                taskContext(task)
                taskProgress(task.progress)
                Button(viewModel.selectedTaskHasActiveDescendants ? "Mark parent and children done" : "Mark done") {
                    _ = viewModel.completeSelectedTask(includingDescendants: viewModel.selectedTaskHasActiveDescendants)
                }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 2)
                    .accessibilityLabel(viewModel.selectedTaskHasActiveDescendants ? "Mark \(task.title) and its child tasks done" : "Mark \(task.title) done")
            }
            .frame(maxWidth: 360, alignment: .leading)
            .padding(14)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
        } else if let suggestion = viewModel.nextTaskSuggestion {
            VStack(spacing: 5) {
                Text("No task selected")
                    .font(.subheadline.weight(.semibold))
                Text("Next suggestion: \(suggestion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func taskContext(_ task: FocusTimerViewModel.CurrentTask) -> some View {
        let details = [task.project, task.context].compactMap { $0 }.joined(separator: " · ")
        if !details.isEmpty {
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if let deadline = task.deadline {
            Text("Due \(deadline.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func taskProgress(_ progress: FocusTimerViewModel.CurrentTask.Progress) -> some View {
        switch progress {
        case let .unknown(actualWorkSeconds):
            Text(actualWorkSeconds > 0
                 ? "Time unknown · \(durationText(actualWorkSeconds)) focused"
                 : "Time unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .estimated(remainingSeconds, actualWorkSeconds):
            Text("\(durationText(remainingSeconds)) remaining · \(durationText(actualWorkSeconds)) focused")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .estimateUsed(actualWorkSeconds):
            Text("Estimate used · \(durationText(actualWorkSeconds)) focused · still open")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let roundedMinutes = max(1, Int((seconds / 60).rounded()))
        return "\(roundedMinutes) min"
    }

    private var primaryControl: some View {
        ZStack {
            if holdProgress > 0 {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: geometry.size.width * holdProgress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(primaryControlTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .foregroundStyle(.white)
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 32)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHoldIfNeeded() }
                .onEnded { _ in endHold() }
        )
    }

    private var primaryControlTitle: String {
        switch viewModel.phase {
        case .idle:
            return "Start"
        case .work:
            return "Focus (hold to take a break)"
        case .break:
            return "Skip break (hold)"
        case .shortBreak:
            return "Skip short break (hold)"
        case .longBreak:
            return "Skip long break (hold)"
        case .completedDay:
            return "Complete"
        }
    }

    private var currentHoldDuration: TimeInterval {
        (viewModel.phase == .break || viewModel.phase == .shortBreak || viewModel.phase.isLongBreak) ? Self.breakHoldDuration : Self.workHoldDuration
    }

    private func beginHoldIfNeeded() {
        guard (viewModel.phase == .work || viewModel.phase == .break || viewModel.phase == .shortBreak || viewModel.phase.isLongBreak),
              holdTimer == nil
        else { return }
        holdProgress = 0
        let holdDuration = currentHoldDuration
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdTickInterval, repeats: true) { timer in
            holdProgress += CGFloat(Self.holdTickInterval / holdDuration)
            if holdProgress >= 1 {
                timer.invalidate()
                holdTimer = nil
                holdProgress = 0
                pickerDuration = viewModel.midWorkBreakPickerDefault
                viewModel.completeHoldToInterrupt()
            }
        }
    }

    private func endHold() {
        let wasHolding = holdTimer != nil
        holdTimer?.invalidate()
        holdTimer = nil
        holdProgress = 0

        if viewModel.phase == .idle, !wasHolding {
            viewModel.start()
        }
    }

    private var breakDurationPicker: some View {
        NavigationStack {
            Form {
                if viewModel.usesSecondScaleBreakPicker {
                    LabeledContent("Break length", value: "\(Int(pickerDuration)) sec")
                    Text("This short duration comes from the active manual-test rhythm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Stepper(
                        "Break length: \(Int(pickerDuration / 60)) min",
                        value: Binding(
                            get: { Int(pickerDuration / 60) },
                            set: { pickerDuration = TimeInterval($0 * 60) }
                        ),
                        in: 1...Int(FocusTimerViewModel.midWorkBreakCap / 60),
                        step: 1
                    )
                    Text("Mid-work breaks are capped at \(Int(FocusTimerViewModel.midWorkBreakCap / 60)) minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Take a break")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelBreakSelection() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start break") { viewModel.confirmBreak(duration: pickerDuration) }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var endCycleWordCount: Int {
        FocusTimerViewModel.wordCount(endCycleReasoning)
    }

    private var endCycleSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Do you really need to stop, or can you wait until the next break?")
                        .font(.body)
                }
                Section("Your reasoning (at least \(FocusTimerViewModel.endCycleMinimumWordCount) words)") {
                    TextEditor(text: $endCycleReasoning)
                        .frame(minHeight: 120)
                    Text("\(endCycleWordCount) / \(FocusTimerViewModel.endCycleMinimumWordCount) words")
                        .font(.caption)
                        .foregroundStyle(endCycleWordCount >= FocusTimerViewModel.endCycleMinimumWordCount ? Color.secondary : Color.orange)
                }
            }
            .navigationTitle("End for today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep going") { viewModel.cancelEndCycle() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stop") {
                        if viewModel.confirmEndCycle(reasoning: endCycleReasoning) {
                            onEndDay()
                        }
                    }
                        .disabled(endCycleWordCount < FocusTimerViewModel.endCycleMinimumWordCount)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var durationControls: some View {
        VStack(spacing: 8) {
            Stepper(
                "Work: \(Int(viewModel.workDuration / 60)) min",
                value: Binding(
                    get: { Int(viewModel.workDuration / 60) },
                    set: { viewModel.updateDurations(workDuration: TimeInterval($0 * 60), breakDuration: viewModel.breakDuration) }
                ),
                in: 1...120,
                step: 1
            )
            Stepper(
                "Break: \(Int(viewModel.breakDuration / 60)) min",
                value: Binding(
                    get: { Int(viewModel.breakDuration / 60) },
                    set: { viewModel.updateDurations(workDuration: viewModel.workDuration, breakDuration: TimeInterval($0 * 60)) }
                ),
                in: 1...30,
                step: 1
            )
        }
        .padding(.horizontal, 32)
        .foregroundStyle(.secondary)
    }

    private var accessibilityTimeLabel: String {
        viewModel.remainingTimeText.replacingOccurrences(of: ":", with: " minutes and ") + " seconds"
    }
}

#Preview {
    TimerHomeView()
}
