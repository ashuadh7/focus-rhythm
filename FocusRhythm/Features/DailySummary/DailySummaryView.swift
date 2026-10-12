import SwiftUI

struct DailySummaryView: View {
    @State private var viewModel: DailySummaryViewModel
    @Environment(\.dismiss) private var dismiss

    init(now: @escaping () -> Date = Date.init) {
        _viewModel = State(initialValue: DailySummaryViewModel(now: now))
    }

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
                if let review = viewModel.taskReview {
                    taskReviewSection(review)
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

    private func taskReviewSection(_ review: DayEndReview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Work review")
                .font(.headline)
            Text("Focused \(durationText(review.actualWorkSeconds)) on tasks. \(review.completedTaskIDs.count) completed · \(review.unfinishedTaskIDs.count) unfinished")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if review.hasUnknownRemainingEffort {
                Text("Some unfinished work has time unknown.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(durationText(review.remainingKnownEffortSeconds)) known work remains.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !review.forecast.conflicts.isEmpty {
                Text("Your next-day preview has capacity, deadline, or prerequisite items to review.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            ForEach(review.taskRows) { row in
                taskReviewRow(row, carriedForward: review.carryoverTaskIDs.contains(row.id))
            }
            if let message = viewModel.carryoverMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }

    private func taskReviewRow(_ row: DayEndReview.TaskRow, carriedForward: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.task.title)
                    .font(.body.weight(.medium))
                Spacer()
                if row.task.completedAt != nil {
                    Text("Done")
                        .foregroundStyle(.green)
                } else if carriedForward {
                    Text("For later")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unfinished")
                        .foregroundStyle(.secondary)
                }
            }
            if let parent = row.parentTitle {
                Text("Part of \(parent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("This task: \(durationText(row.ownActualWorkSeconds)) focused · \(remainingText(row.task.remainingEstimateSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if row.task.parentTaskID == nil, row.rolledUpActualWorkSeconds != row.ownActualWorkSeconds {
                Text("Including child tasks: \(durationText(row.rolledUpActualWorkSeconds)) focused · \(rollupRemainingText(row))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if row.task.completedAt == nil && row.task.abandonedAt == nil {
                Button(carriedForward ? "Return to active queue" : "Carry forward for review") {
                    if carriedForward {
                        viewModel.returnFromCarryover(row.id)
                    } else {
                        viewModel.carryForward(row.id)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 5)
    }

    private func remainingText(_ seconds: TimeInterval?) -> String {
        seconds.map { "\(durationText($0)) remaining" } ?? "time unknown"
    }

    private func rollupRemainingText(_ row: DayEndReview.TaskRow) -> String {
        row.hasUnknownRemainingEffort ? "time unknown remains" : remainingText(row.rolledUpRemainingEstimateSeconds)
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
