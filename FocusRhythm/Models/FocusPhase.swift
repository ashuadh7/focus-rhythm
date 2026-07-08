enum FocusPhase: Equatable {
    case idle
    case work
    case `break`
    case workPaused
    case breakPaused

    var isRunning: Bool {
        self == .work || self == .break
    }

    var isPaused: Bool {
        self == .workPaused || self == .breakPaused
    }
}
