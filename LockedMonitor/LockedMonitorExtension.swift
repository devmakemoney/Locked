//
//  LockedMonitorExtension.swift
//  LockedMonitor
//
//  iOS wakes this extension at every schedule boundary. It never decides
//  anything on its own — it just asks ShieldEngine to recompute, so the app and
//  the extension can never disagree about what should be blocked.
//

import DeviceActivity
import ManagedSettings
import Foundation

class LockedMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        SharedStore.migrateIfNeeded()
        NSLog("[LockedMonitor] start \(activity.rawValue)")
        ShieldEngine.apply()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        NSLog("[LockedMonitor] end \(activity.rawValue)")

        if activity == ScheduleManager.overrideActivityName {
            SharedStore.clearOverride()
        }

        // Re-arm the rolling window so the schedule keeps running even if the
        // app is never opened again.
        ScheduleManager.refresh()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        ShieldEngine.apply()
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }
}
