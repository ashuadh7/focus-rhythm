import SwiftUI

struct TimerHomeView: View {
    @State private var viewModel = FocusTimerViewModel()
    @State private var waterLoggingViewModel = WaterLoggingViewModel()
    @State private var isShowingSummary = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var pickerDuration: TimeInterval = FocusTimerViewModel.defaultBreakDuration
    @State private var endCycleReasoning = ""

    private static let workHoldDuration: TimeInterval = 5
    private static let breakHoldDuration: TimeInterval = 3
    private static let holdTickInterval: TimeInterval = 0.05

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        content
            .sheet(isPresented: $isShowingSummary) {
                DailySummaryView()
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
    }

    private var content: some View {
        VStack(spacing: 32) {
            HStack {
                Spacer()
                Button("Today") { isShowingSummary = true }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Text(viewModel.phaseTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(viewModel.remainingTimeText)
                    .font(.system(size: 84, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel(accessibilityTimeLabel)

                if viewModel.isBonusLowTimeWarningVisible {
                    Text("Bonus time almost up")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                } else if viewModel.isLowTimeWarningVisible {
                    Text("Running low")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }

                if viewModel.phase == .break {
                    WaterPromptView(viewModel: waterLoggingViewModel)
                } else {
                    Text(viewModel.prompt)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            primaryControl

            if viewModel.isAddTimeAvailable {
                Button("Add time") { viewModel.addTime() }
                    .font(.subheadline.weight(.medium))
            }

            if viewModel.phase == .idle {
                durationControls
            } else {
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
            viewModel.tick()
        }
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
            return "Break (hold to skip)"
        }
    }

    private var currentHoldDuration: TimeInterval {
        viewModel.phase == .break ? Self.breakHoldDuration : Self.workHoldDuration
    }

    private func beginHoldIfNeeded() {
        guard viewModel.phase.isRunning, holdTimer == nil else { return }
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
                    Button("Stop") { viewModel.confirmEndCycle(reasoning: endCycleReasoning) }
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
