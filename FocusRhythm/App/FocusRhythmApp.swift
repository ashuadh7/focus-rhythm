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
    @State private var activeRun: ActiveRhythmRun?

    var body: some View {
        if let activeRun {
            TimerHomeView(
                workDuration: activeRun.rhythm.workDuration,
                breakDuration: activeRun.rhythm.shortBreakDuration,
                onEndDay: {
                    self.activeRun = nil
                }
            )
        } else {
            RhythmSetupView { run in
                activeRun = run
            }
        }
    }
}
