//
//  ScheduleRule.swift
//  Locked — shared between the app and the LockedMonitor extension
//
//  A rule says: "block profile X on these weekdays, from HH:mm to HH:mm".
//  Every day is independent — a rule carries its own set of weekdays, and you
//  can create as many rules as you want for the same day.
//

import Foundation

struct ScheduleRule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    /// The profile whose apps get shielded while this rule is active.
    var profileID: UUID
    /// Calendar convention: 1 = Sunday, 2 = Monday, … 7 = Saturday.
    var weekdays: Set<Int>
    /// Minutes since midnight, 0…1439.
    var startMinutes: Int
    /// Minutes since midnight. If <= startMinutes the window crosses midnight.
    var endMinutes: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        profileID: UUID,
        weekdays: Set<Int>,
        startMinutes: Int,
        endMinutes: Int,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.profileID = profileID
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.isEnabled = isEnabled
    }

    var crossesMidnight: Bool { endMinutes <= startMinutes }

    /// Total duration in minutes, midnight-crossing included.
    var durationMinutes: Int {
        crossesMidnight ? (1440 - startMinutes) + endMinutes : endMinutes - startMinutes
    }

    /// Is this rule active at `date`? Computed straight from the rule, never
    /// from stored state — so a missed DeviceActivity callback cannot leave the
    /// shield stuck on or off.
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, !weekdays.isEmpty else { return false }

        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = comps.weekday, let hour = comps.hour, let minute = comps.minute else {
            return false
        }
        let nowMinutes = hour * 60 + minute

        if !crossesMidnight {
            return weekdays.contains(weekday)
                && nowMinutes >= startMinutes
                && nowMinutes < endMinutes
        }

        // Crossing midnight: the tail belongs to the *previous* day's rule.
        if weekdays.contains(weekday) && nowMinutes >= startMinutes { return true }
        let previousWeekday = weekday == 1 ? 7 : weekday - 1
        if weekdays.contains(previousWeekday) && nowMinutes < endMinutes { return true }
        return false
    }

    // MARK: - Display helpers

    static func timeLabel(_ minutes: Int) -> String {
        String(format: "%02dh%02d", minutes / 60, minutes % 60)
    }

    var rangeLabel: String {
        "\(Self.timeLabel(startMinutes)) – \(Self.timeLabel(endMinutes))"
            + (crossesMidnight ? " (+1j)" : "")
    }

    var weekdaysLabel: String {
        if weekdays.count == 7 { return "Tous les jours" }
        if weekdays == [2, 3, 4, 5, 6] { return "Lun – Ven" }
        if weekdays == [1, 7] { return "Week-end" }
        return Self.orderedWeekdays
            .filter { weekdays.contains($0) }
            .map { Self.shortName($0) }
            .joined(separator: " ")
    }

    /// Monday-first ordering for the UI, Calendar numbering underneath.
    static let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

    static func shortName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Dim"
        case 2: return "Lun"
        case 3: return "Mar"
        case 4: return "Mer"
        case 5: return "Jeu"
        case 6: return "Ven"
        case 7: return "Sam"
        default: return "?"
        }
    }
}

// MARK: - Segments

/// A rule flattened into a concrete window on a concrete calendar day.
/// DeviceActivity needs absolute dates, and it cannot represent a window that
/// crosses midnight — so a crossing rule yields two segments.
struct ScheduleSegment {
    let ruleID: UUID
    let start: Date
    let end: Date

    /// Stable, short enough for DeviceActivityName.
    var activityName: String {
        let stamp = Int(start.timeIntervalSince1970)
        return "seg_\(ruleID.uuidString.prefix(8))_\(stamp)"
    }
}

extension ScheduleRule {
    /// Concrete windows for this rule over `days` days starting at midnight
    /// of `from`'s day. Windows already finished are dropped.
    func segments(from reference: Date, days: Int, calendar: Calendar = .current) -> [ScheduleSegment] {
        guard isEnabled, !weekdays.isEmpty, durationMinutes > 0 else { return [] }

        var result: [ScheduleSegment] = []
        let midnight = calendar.startOfDay(for: reference)

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: midnight) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekdays.contains(weekday) else { continue }
            guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: day) else { continue }

            if crossesMidnight {
                // Tail of the day, then the head of the next one.
                if let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) {
                    result.append(ScheduleSegment(ruleID: id, start: start, end: endOfDay.addingTimeInterval(-60)))
                    if endMinutes > 0,
                       let nextEnd = calendar.date(byAdding: .minute, value: endMinutes, to: endOfDay) {
                        result.append(ScheduleSegment(ruleID: id, start: endOfDay, end: nextEnd))
                    }
                }
            } else if let end = calendar.date(byAdding: .minute, value: endMinutes, to: day) {
                result.append(ScheduleSegment(ruleID: id, start: start, end: end))
            }
        }

        return result.filter { $0.end > reference }
    }
}
