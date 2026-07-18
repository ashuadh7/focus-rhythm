import SwiftUI

struct DailySummaryView: View {
    @State private var viewModel = DailySummaryViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 24) {
                    summaryRow(title: "Focus time", value: focusTimeText)
                    summaryRow(title: "Cycles completed", value: "\(viewModel.cycleCount)")
                    summaryRow(title: "Water logged", value: waterText)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { viewModel.refresh() }
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var focusTimeText: String {
        let totalMinutes = Int(viewModel.totalFocusTime) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var waterText: String {
        "\(viewModel.totalWaterMl) ml"
    }
}

#Preview {
    DailySummaryView()
}
