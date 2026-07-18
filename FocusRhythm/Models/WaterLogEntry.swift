import Foundation

struct WaterLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let amountMl: Int
    let loggedAt: Date
}
