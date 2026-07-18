enum FocusPhase: Equatable {
    case idle
    case work
    case `break`

    var isRunning: Bool {
        self == .work || self == .break
    }
}
