import SwiftUI

@main
struct FocusRhythmApp: App {
    var body: some Scene {
        WindowGroup {
            AppEntryView()
        }
    }
}

private struct AppEntryView: View {
    @State private var clock: AppClock
    @State private var activeRun: ActiveRhythmRun?
    @State private var stoppedRun: StoppedRhythmRun?

    private let activeRunStore = UserDefaultsActiveRunStore()
    private let stoppedRunStore = UserDefaultsStoppedRunStore()
    private let runHistoryStore = UserDefaultsRunHistoryStore()

    init() {
        let clock = AppClock()
        _clock = State(initialValue: clock)
        _activeRun = State(initialValue: ActiveRunRestorer(now: { clock.now }).restore())
        _stoppedRun = State(initialValue: UserDefaultsStoppedRunStore().load())
    }

    @ViewBuilder
    var body: some View {
#if DEBUG
        content
            .safeAreaInset(edge: .bottom) {
                debugClockControls
            }
#else
        content
#endif
    }

    @ViewBuilder
    private var content: some View {
        if let activeRun {
            TimerHomeView(
                run: activeRun,
                clock: clock,
                onEndDay: {
                    self.activeRun = nil
                    self.stoppedRun = stoppedRunStore.load()
                }
            )
        } else if let stoppedRun {
            StoppedRunReviewView(
                run: stoppedRun,
                onContinue: continueRun,
                onDiscard: discardRun
            )
        } else {
            RhythmSetupView(clock: clock) { run in
                activeRun = run
            }
        }
    }

    private func continueRun(_ itemIDs: Set<UUID>) {
        guard let stoppedRun,
              let run = stoppedRun.continuedRun(using: itemIDs, at: clock.now)
        else { return }
        activeRunStore.save(run)
        stoppedRunStore.clear()
        self.stoppedRun = nil
        activeRun = run
    }

    private func discardRun() {
        guard var sourceRun = stoppedRun?.sourceRun else { return }
        sourceRun.status = .ended
        activeRunStore.save(sourceRun)
        runHistoryStore.record(CompletedRhythmRun(
            id: sourceRun.id,
            startedAt: sourceRun.startedAt,
            schedule: sourceRun.schedule,
            outcome: .endedEarly,
            adjustments: sourceRun.adjustments
        ))
        activeRunStore.clear()
        stoppedRunStore.clear()
        stoppedRun = nil
    }

#if DEBUG
    private var debugClockControls: some View {
        HStack(spacing: 12) {
            Text("Clock")
                .font(.caption.weight(.semibold))
            Picker("Clock rate", selection: Binding(
                get: { clock.rate },
                set: { clock.setRate($0) }
            )) {
                ForEach(AppClock.availableRates, id: \.self) { rate in
                    Text("\(Int(rate))×").tag(rate)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
#endif
}

private struct StoppedRunReviewView: View {
    let run: StoppedRhythmRun
    let onContinue: (Set<UUID>) -> Void
    let onDiscard: () -> Void

    @State private var includedItemIDs: Set<UUID>
    @State private var isConfirmingDiscard = false

    init(
        run: StoppedRhythmRun,
        onContinue: @escaping (Set<UUID>) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.run = run
        self.onContinue = onContinue
        self.onDiscard = onDiscard
        _includedItemIDs = State(initialValue: Set(run.remainingPlan.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Stopped day") {
                    LabeledContent("Focus completed", value: durationText(run.completedFocusTime))
                    LabeledContent("Completed intervals", value: "\(run.completedFocusIntervals)")
                    LabeledContent("Original target", value: durationText(run.originalFocusTarget))
                    LabeledContent("Focus remaining", value: durationText(selectedFocusTime))
                    Text("Stopped \(run.stoppedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(run.remainingPlan) { item in
                        Toggle(isOn: Binding(
                            get: { includedItemIDs.contains(item.id) },
                            set: { included in
                                if included { includedItemIDs.insert(item.id) }
                                else { includedItemIDs.remove(item.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.label ?? title(for: item.kind))
                                Text("\(title(for: item.kind)) · \(durationText(item.duration))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Remaining plan")
                } footer: {
                    Text("Turn off blocks to revise the remainder before continuing. Task identities can be attached here when planning is added.")
                }

                Section {
                    Button("Continue remaining plan") {
                        onContinue(includedItemIDs)
                    }
                    .disabled(selectedFocusTime <= 0)

                    Button("Discard remaining plan", role: .destructive) {
                        isConfirmingDiscard = true
                    }
                }
            }
            .navigationTitle("Review unfinished day")
            .confirmationDialog(
                "Discard the remaining plan?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard plan", role: .destructive, action: onDiscard)
                Button("Keep it", role: .cancel) {}
            }
        }
    }

    private var selectedFocusTime: TimeInterval {
        run.remainingPlan
            .filter { includedItemIDs.contains($0.id) && $0.kind == .focus }
            .reduce(0) { $0 + $1.duration }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if totalMinutes >= 60 { return "\(totalMinutes / 60)h \(totalMinutes % 60)m" }
        if totalMinutes > 0 { return "\(totalMinutes)m" }
        return "\(seconds)s"
    }

    private func title(for kind: ScheduledIntervalKind) -> String {
        switch kind {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case let .longBreak(name): return name
        }
    }
}
