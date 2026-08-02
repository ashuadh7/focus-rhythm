import Foundation

struct TimeOfDay: Codable, Equatable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    var isValid: Bool {
        (0..<24).contains(hour) && (0..<60).contains(minute)
    }
}

struct WorkSection: Codable, Equatable, Hashable {
    var startTime: TimeOfDay
    var endTime: TimeOfDay

    init(startTime: TimeOfDay, endTime: TimeOfDay) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct AnchoredLongBreak: Codable, Equatable, Hashable {
    var name: String
    var startTime: TimeOfDay
    var endTime: TimeOfDay

    init(name: String, startTime: TimeOfDay, endTime: TimeOfDay) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
    }
}

enum FinalPartialFocusBehavior: String, Codable, Equatable {
    case omit
    case trim
}

struct DailyRhythm: Codable, Equatable {
    var name: String
    var dayStart: TimeOfDay
    var dayEnd: TimeOfDay
    var workDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var workSections: [WorkSection]
    var longBreaks: [AnchoredLongBreak]
    var finalPartialFocusBehavior: FinalPartialFocusBehavior

    init(
        name: String,
        dayStart: TimeOfDay,
        dayEnd: TimeOfDay,
        workDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        workSections: [WorkSection],
        longBreaks: [AnchoredLongBreak],
        finalPartialFocusBehavior: FinalPartialFocusBehavior = .omit
    ) {
        self.name = name
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.workDuration = workDuration
        self.shortBreakDuration = shortBreakDuration
        self.workSections = workSections
        self.longBreaks = longBreaks
        self.finalPartialFocusBehavior = finalPartialFocusBehavior
    }
}

enum ScheduledIntervalKind: Codable, Equatable {
    case focus
    case shortBreak
    case longBreak(name: String)
}

struct ScheduledInterval: Codable, Equatable {
    let id: UUID
    let kind: ScheduledIntervalKind
    let startDate: Date
    let endDate: Date
    let isAnchored: Bool
    let label: String?
    let excludedDuration: TimeInterval

    init(
        id: UUID = UUID(),
        kind: ScheduledIntervalKind,
        startDate: Date,
        endDate: Date,
        isAnchored: Bool,
        label: String? = nil,
        excludedDuration: TimeInterval = 0
    ) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.isAnchored = isAnchored
        self.label = label
        self.excludedDuration = excludedDuration
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, startDate, endDate, isAnchored, label, excludedDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(ScheduledIntervalKind.self, forKey: .kind)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        isAnchored = try container.decode(Bool.self, forKey: .isAnchored)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        excludedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .excludedDuration) ?? 0
    }

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate) - excludedDuration)
    }

    var isFlexible: Bool {
        !isAnchored
    }

    static func == (lhs: ScheduledInterval, rhs: ScheduledInterval) -> Bool {
        lhs.kind == rhs.kind
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAnchored == rhs.isAnchored
            && lhs.label == rhs.label
            && lhs.excludedDuration == rhs.excludedDuration
    }
}

struct LongBreakDetails: Equatable {
    let name: String
    let startDate: Date
    let endDate: Date

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

struct GeneratedDailySchedule: Codable, Equatable {
    let rhythmName: String
    let dayStart: Date
    let dayEnd: Date
    let intervals: [ScheduledInterval]

    var expectedFocusTime: TimeInterval {
        intervals
            .filter { $0.kind == .focus }
            .reduce(0) { $0 + $1.duration }
    }

    var focusSessionCount: Int {
        intervals.filter { $0.kind == .focus }.count
    }

    var longBreakDetails: [LongBreakDetails] {
        intervals.compactMap { interval in
            guard case let .longBreak(name) = interval.kind else { return nil }
            return LongBreakDetails(
                name: name,
                startDate: interval.startDate,
                endDate: interval.endDate
            )
        }
    }
}

extension GeneratedDailySchedule {
    struct ReflowResult {
        let schedule: GeneratedDailySchedule
        let appliedAdjustment: TimeInterval
    }

    /// Moves the flexible remainder of the current anchored section while keeping its
    /// closing long break (or day end) fixed. Positive adjustments consume time from
    /// the section's final focus interval; negative adjustments close the gap early.
    func reflowingFlexibleRemainder(
        from cutoff: Date,
        by requestedAdjustment: TimeInterval
    ) -> ReflowResult {
        guard requestedAdjustment != 0,
              let currentIndex = intervals.firstIndex(where: { $0.startDate <= cutoff && cutoff < $0.endDate }),
              intervals[currentIndex].isFlexible
        else { return ReflowResult(schedule: self, appliedAdjustment: 0) }

        let sectionEndIndex = intervals[currentIndex...].firstIndex(where: { $0.isAnchored }) ?? intervals.endIndex
        let boundary = sectionEndIndex < intervals.endIndex ? intervals[sectionEndIndex].startDate : dayEnd
        let sectionIndices = Array(currentIndex..<sectionEndIndex)
        guard !sectionIndices.isEmpty else { return ReflowResult(schedule: self, appliedAdjustment: 0) }

        var remainingDurations = sectionIndices.map { index in
            index == currentIndex ? intervals[index].endDate.timeIntervalSince(cutoff) : intervals[index].duration
        }
        let capacity = max(0, boundary.timeIntervalSince(cutoff))
        let originalTotal = remainingDurations.reduce(0, +)
        var appliedAdjustment = requestedAdjustment

        if requestedAdjustment > 0 {
            let overflow = max(0, originalTotal + requestedAdjustment - capacity)
            if overflow > 0 {
                let lastFocusPosition = sectionIndices.indices.reversed().first {
                    $0 > 0 && intervals[sectionIndices[$0]].kind == .focus
                }
                let absorbable = lastFocusPosition.map { remainingDurations[$0] } ?? 0
                appliedAdjustment -= max(0, overflow - absorbable)
            }
        } else {
            appliedAdjustment = max(requestedAdjustment, -remainingDurations[0])
        }
        remainingDurations[0] = max(0, remainingDurations[0] + appliedAdjustment)

        var overflow = max(0, remainingDurations.reduce(0, +) - capacity)
        if overflow > 0,
           let lastFocusPosition = sectionIndices.indices.reversed().first(where: {
               $0 > 0 && intervals[sectionIndices[$0]].kind == .focus
           }) {
            let reduction = min(overflow, remainingDurations[lastFocusPosition])
            remainingDurations[lastFocusPosition] -= reduction
            overflow -= reduction
        }
        guard overflow == 0 else { return ReflowResult(schedule: self, appliedAdjustment: 0) }

        var rebuilt = Array(intervals[..<currentIndex])
        var cursor = cutoff
        for (position, index) in sectionIndices.enumerated() {
            let source = intervals[index]
            let duration = remainingDurations[position]
            guard duration > 0 else { continue }
            let start = index == currentIndex ? source.startDate : cursor
            let end = cursor.addingTimeInterval(duration)
            rebuilt.append(ScheduledInterval(
                id: source.id,
                kind: source.kind,
                startDate: start,
                endDate: end,
                isAnchored: false,
                label: source.label,
                excludedDuration: source.excludedDuration
            ))
            cursor = end
        }
        rebuilt.append(contentsOf: intervals[sectionEndIndex...])

        return ReflowResult(
            schedule: GeneratedDailySchedule(
                rhythmName: rhythmName,
                dayStart: dayStart,
                dayEnd: dayEnd,
                intervals: rebuilt
            ),
            appliedAdjustment: appliedAdjustment
        )
    }
}
