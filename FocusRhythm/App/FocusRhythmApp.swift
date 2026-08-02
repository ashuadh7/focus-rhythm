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
    @State private var activeRun: ActiveRhythmRun? = ActiveRunRestorer().restore()

    var body: some View {
        if let activeRun {
            TimerHomeView(
                run: activeRun,
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
