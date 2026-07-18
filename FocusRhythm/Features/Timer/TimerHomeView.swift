import SwiftUI

struct TimerHomeView: View {
    @State private var viewModel = FocusTimerViewModel()
    @State private var waterLoggingViewModel = WaterLoggingViewModel()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 32) {
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

                if viewModel.phase == .break || viewModel.phase == .breakPaused {
                    WaterPromptView(viewModel: waterLoggingViewModel)
                } else {
                    Text(viewModel.prompt)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Button(action: viewModel.togglePrimaryAction) {
                Text(viewModel.primaryActionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            if viewModel.phase == .idle {
                durationControls
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .onReceive(ticker) { _ in
            viewModel.tick()
        }
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
