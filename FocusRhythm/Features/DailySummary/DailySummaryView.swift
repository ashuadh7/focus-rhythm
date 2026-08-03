import SwiftUI

struct DailySummaryView: View {
    @State private var viewModel = DailySummaryViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {

                VStack(spacing: 24) {
                    summaryRow(title: "Focus planned", value: plannedFocusTimeText)
                    summaryRow(title: "Focus actual", value: focusTimeText)
                    summaryRow(title: "Sessions", value: "\(viewModel.cycleCount) of \(viewModel.plannedCycleCount)")
                    summaryRow(title: "Water logged", value: waterText)
                    if let outcome = viewModel.runOutcome {
                        Text(outcome == .completedAsPlanned ? "Completed at the planned end" : "Ended for today")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 32)

                if !viewModel.runSummaries.isEmpty {
                    detailSection
                }
                }
            }
            .padding(.vertical, 32)
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
        durationText(viewModel.totalFocusTime)
    }

    private var plannedFocusTimeText: String {
        durationText(viewModel.plannedFocusTime)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
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

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sessions")
                .font(.headline)
            ForEach(Array(viewModel.runSummaries.enumerated()), id: \.element.id) { index, run in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Session \(index + 1) · \(run.startedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.body.weight(.semibold))
                    Text(run.outcome == .completedAsPlanned ? "Completed at the planned end" : "Ended for today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(durationText(run.plannedFocusTime)) planned · \(run.plannedCycleCount) focus sessions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(run.activities) { activity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title)
                                .font(.body.weight(.medium))
                            Text("\(durationText(activity.actualDuration)) focused of \(durationText(activity.plannedDuration)) planned")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(run.adjustments) { adjustment in
                        Text(adjustmentText(adjustment))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }

    private func adjustmentText(_ adjustment: RunAdjustment) -> String {
        let time = durationText(adjustment.duration)
        switch adjustment.kind {
        case .midWorkBreak: return "Took an extra \(time) break during \(adjustment.label)"
        case .skippedBreak: return "Skipped \(time) of \(adjustment.label)"
        case .extendedFocus: return "Extended \(adjustment.label) by \(time)"
        case .extendedLongBreak: return "Extended \(adjustment.label) by \(time)"
        }
    }
}

#Preview {
    DailySummaryView()
}
