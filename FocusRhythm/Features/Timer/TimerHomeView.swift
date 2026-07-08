import SwiftUI

struct TimerHomeView: View {
    @State private var viewModel = FocusTimerViewModel()

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

                Text(viewModel.prompt)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var accessibilityTimeLabel: String {
        viewModel.remainingTimeText.replacingOccurrences(of: ":", with: " minutes and ") + " seconds"
    }
}

#Preview {
    TimerHomeView()
}
