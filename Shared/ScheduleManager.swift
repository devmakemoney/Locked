//
//  ScheduleManager.swift
//  Locked — shared between the app and the LockedMonitor extension
//
//  Turns rules into DeviceActivity monitoring windows.
//
//  Design note: DeviceActivity is only used as an *alarm clock* — it wakes the
//  extension at the boundaries. What actually gets blocked is always recomputed
//  by ShieldEngine from the rules and the current time. That keeps us correct
//  even when iOS drops a callback.
//
//  iOS caps how many activities one app may monitor at once (20 in practice),
//  so we schedule a rolling window of the next few days and re-arm it every
//  time a window ends.
//

import Foundation
import DeviceActivity

enum ScheduleManager {
    private static let center = DeviceActivityCenter()

    /// Kept under the platform cap, with headroom for the override window.
    static let maxActivities = 18
    /// How far ahead we arm windows. Re-armed on every boundary and app launch.
    static let horizonDays = 3

    static let overrideActivityName = DeviceActivityName("nfc_override")

    /// Rebuild the whole monitoring set, then push the shield.
    static func refresh(now: Date = Date()) {
        center.stopMonitoring()

        guard SharedStore.scheduleEnabled else {
            ShieldEngine.clear()
            return
        }

        var segments = SharedStore.rules
            .flatMap { $0.segments(from: now, days: horizonDays) }
            .sorted { $0.start < $1.start }

        // Drop duplicates that would collide on the same activity name.
        var seen = Set<String>()
        segments = segments.filter { seen.insert($0.activityName).inserted }

        if segments.count > maxActivities {
            NSLog("[Locked] \(segments.count) windows over the horizon, keeping the first \(maxActivities)")
            segments = Array(segments.prefix(maxActivities))
        }

        for segment in segments {
            let schedule = DeviceActivitySchedule(
                intervalStart: components(from: segment.start),
                intervalEnd: components(from: segment.end),
                repeats: false
            )
            do {
                try center.startMonitoring(DeviceActivityName(segment.activityName), during: schedule)
            } catch {
                NSLog("[Locked] could not monitor \(segment.activityName): \(error.localizedDescription)")
            }
        }

        if SharedStore.isOverrideActive, let until = SharedStore.overrideUntil {
            armOverrideEnd(at: until, now: now)
        }

        ShieldEngine.apply(at: now)
    }

    /// Wakes us when the NFC unlock expires so the shield comes back even if
    /// the app never returns to the foreground.
    static func armOverrideEnd(at until: Date, now: Date = Date()) {
        // DeviceActivity refuses windows shorter than 15 minutes.
        let end = max(until, now.addingTimeInterval(15 * 60 + 60))
        let schedule = DeviceActivitySchedule(
            intervalStart: components(from: now.addingTimeInterval(60)),
            intervalEnd: components(from: end),
            repeats: false
        )
        try? center.startMonitoring(overrideActivityName, during: schedule)
    }

    private static func components(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }
}
