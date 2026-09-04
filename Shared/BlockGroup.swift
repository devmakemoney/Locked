//
//  BlockGroup.swift
//  Créneau — shared between the app and the LockedMonitor extension
//
//  A group is "these apps, blocked during these windows".
//
//  The apps are chosen once, at the group level. The windows are what varies:
//  Loisir is one set of apps blocked from 00h to 08h, then 10h to 14h, then 17h
//  to midnight. Modelling each window as its own rule forced you to re-pick the
//  same apps three times, which is why this exists.
//
//  Pure Foundation on purpose: the date logic is the fragile part, and this way
//  it can be compiled and tested outside iOS. The app selections live in
//  SharedStore, keyed by group id.
//

import Foundation

// MARK: - Time window

/// One range on a set of weekdays. If `endMinutes` <= `startMinutes` the window
/// crosses midnight and its tail belongs to the day it started on.
struct TimeWindow: Identifiable, Codable, Hashable {
    var id: UUID
    /// Calendar convention: 1 = Sunday, 2 = Monday, … 7 = Saturday.
    var weekdays: Set<Int>
    /// Minutes since midnight, 0…1439.
    var startMinutes: Int
    var endMinutes: Int

    init(id: UUID = UUID(), weekdays: Set<Int>, startMinutes: Int, endMinutes: Int) {
        self.id = id
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    var crossesMidnight: Bool { endMinutes <= startMinutes }

    var durationMinutes: Int {
        crossesMidnight ? (1440 - startMinutes) + endMinutes : endMinutes - startMinutes
    }

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard !weekdays.isEmpty, durationMinutes > 0 else { return false }

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

        if weekdays.contains(weekday) && nowMinutes >= startMinutes { return true }
        let previousWeekday = weekday == 1 ? 7 : weekday - 1
        if weekdays.contains(previousWeekday) && nowMinutes < endMinutes { return true }
        return false
    }

    // MARK: Display

    var rangeLabel: String {
        "\(TimeWindow.timeLabel(startMinutes)) – \(TimeWindow.timeLabel(endMinutes))"
            + (crossesMidnight ? " (+1j)" : "")
    }

    var durationLabel: String {
        let total = durationMinutes
        if total < 60 { return "\(total) min" }
        let minutes = total % 60
        return minutes == 0 ? "\(total / 60) h" : "\(total / 60) h \(minutes)"
    }

    var weekdaysLabel: String {
        if weekdays.count == 7 { return "Tous les jours" }
        if weekdays == [2, 3, 4, 5, 6] { return "Lun – Ven" }
        if weekdays == [1, 7] { return "Week-end" }
        return TimeWindow.orderedWeekdays
            .filter { weekdays.contains($0) }
            .map { TimeWindow.shortName($0) }
            .joined(separator: " ")
    }

    static func timeLabel(_ minutes: Int) -> String {
        String(format: "%02dh%02d", minutes / 60, minutes % 60)
    }

    /// Monday-first for the UI, Calendar numbering underneath.
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

// MARK: - Block group

struct BlockGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var windows: [TimeWindow]
    /// Bare domains, e.g. "reddit.com". Blocked alongside the group's apps.
    var webDomains: [String]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        windows: [TimeWindow] = [],
        webDomains: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.windows = windows
        self.webDomains = webDomains
        self.isEnabled = isEnabled
    }

    // Hand-written so groups saved before webDomains existed still decode:
    // the synthesized initialiser would throw on the missing key and wipe
    // everything the user had configured.
    enum CodingKeys: String, CodingKey {
        case id, name, windows, webDomains, isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        windows = try c.decode([TimeWindow].self, forKey: .windows)
        webDomains = try c.decodeIfPresent([String].self, forKey: .webDomains) ?? []
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
    }

    /// Strips scheme, www and trailing slash so "https://www.reddit.com/" and
    /// "reddit.com" cannot end up as two different entries.
    static func normalizeDomain(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if let slash = text.firstIndex(of: "/") { text = String(text[text.startIndex..<slash]) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard text.contains("."), !text.contains(" ") else { return nil }
        return text
    }

    /// Active as soon as any of its windows is. Computed from the clock, never
    /// from stored state, so a dropped DeviceActivity callback self-heals.
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        return windows.contains { $0.isActive(at: date, calendar: calendar) }
    }

    /// Earliest start across the windows, for a stable sort in the list.
    var earliestStart: Int {
        windows.map(\.startMinutes).min() ?? 0
    }

    var summaryLabel: String {
        switch windows.count {
        case 0: return "Aucune plage"
        case 1: return windows[0].rangeLabel
        default: return "\(windows.count) plages"
        }
    }

    /// Total blocked minutes per week — the number that tells you whether a
    /// group is doing anything.
    var weeklyMinutes: Int {
        windows.reduce(0) { $0 + $1.durationMinutes * $1.weekdays.count }
    }
}

// MARK: - Segments

/// A window flattened onto a concrete calendar day. DeviceActivity needs
/// absolute dates and cannot express a range crossing midnight, so a crossing
/// window yields two segments.
struct ScheduleSegment {
    let groupID: UUID
    let start: Date
    let end: Date

    var activityName: String {
        let stamp = Int(start.timeIntervalSince1970)
        return "seg_\(groupID.uuidString.prefix(8))_\(stamp)"
    }
}

extension TimeWindow {
    func segments(groupID: UUID, from reference: Date, days: Int, calendar: Calendar = .current) -> [ScheduleSegment] {
        guard !weekdays.isEmpty, durationMinutes > 0 else { return [] }

        var result: [ScheduleSegment] = []
        let midnight = calendar.startOfDay(for: reference)

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: midnight) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekdays.contains(weekday) else { continue }
            guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: day) else { continue }

            if crossesMidnight {
                if let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) {
                    result.append(ScheduleSegment(groupID: groupID, start: start, end: endOfDay.addingTimeInterval(-60)))
                    if endMinutes > 0,
                       let nextEnd = calendar.date(byAdding: .minute, value: endMinutes, to: endOfDay) {
                        result.append(ScheduleSegment(groupID: groupID, start: endOfDay, end: nextEnd))
                    }
                }
            } else if let end = calendar.date(byAdding: .minute, value: endMinutes, to: day) {
                result.append(ScheduleSegment(groupID: groupID, start: start, end: end))
            }
        }

        return result.filter { $0.end > reference }
    }
}

extension BlockGroup {
    func segments(from reference: Date, days: Int, calendar: Calendar = .current) -> [ScheduleSegment] {
        guard isEnabled else { return [] }
        return windows.flatMap { $0.segments(groupID: id, from: reference, days: days, calendar: calendar) }
    }
}
