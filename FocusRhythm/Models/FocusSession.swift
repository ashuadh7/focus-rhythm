import Foundation

struct FocusSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let completed: Bool
}
