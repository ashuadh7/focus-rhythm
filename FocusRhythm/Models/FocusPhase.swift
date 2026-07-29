enum FocusPhase: Equatable {
    case idle
    case work
    /// Legacy free-running break state retained for saved v0.1 behavior.
    case `break`
    case shortBreak
    case longBreak(name: String)
    case completedDay

    var isRunning: Bool {
        switch self {
        case .work, .break, .shortBreak, .longBreak:
            return true
        case .idle, .completedDay:
            return false
        }
    }
}
