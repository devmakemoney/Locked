//
//  ShieldEngine.swift
//  Locked — shared between the app and the LockedMonitor extension
//
//  Single source of truth for "what should be blocked right now".
//
//  The state is always recomputed from the rules and the clock, never
//  accumulated. A missed DeviceActivity callback therefore self-heals: the next
//  time either the app or the extension runs, the shield snaps back to correct.
//

import Foundation
import FamilyControls
import ManagedSettings

enum ShieldEngine {
    static let store = ManagedSettingsStore()

    /// Groups that should be blocking at `date`, override taken into account.
    static func activeGroups(at date: Date = Date()) -> [BlockGroup] {
        guard SharedStore.scheduleEnabled else { return [] }

        let overridden = SharedStore.isOverrideActive ? SharedStore.overriddenGroupIDs : []
        return SharedStore.groups.filter { group in
            group.isActive(at: date) && !overridden.contains(group.id)
        }
    }

    /// Recompute and push the shield. Idempotent — safe to call from anywhere,
    /// any number of times.
    @discardableResult
    static func apply(at date: Date = Date()) -> [BlockGroup] {
        if let until = SharedStore.overrideUntil, until <= date {
            SharedStore.clearOverride()
        }

        let groups = activeGroups(at: date)
        guard !groups.isEmpty else {
            clear()
            return []
        }

        let selections = SharedStore.selections
        var blockedApps = Set<ApplicationToken>()
        var blockedCategories = Set<ActivityCategoryToken>()

        for group in groups {
            guard let selection = selections[group.id] else { continue }
            blockedApps.formUnion(selection.applicationTokens)
            blockedCategories.formUnion(selection.categoryTokens)
        }

        store.shield.applications = blockedApps.isEmpty ? nil : blockedApps
        store.shield.applicationCategories = blockedCategories.isEmpty
            ? ShieldSettings.ActivityCategoryPolicy.none
            : .specific(blockedCategories)

        // Locked cannot be deleted while it is enforcing something.
        store.application.denyAppRemoval = true
        return groups
    }

    static func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.application.denyAppRemoval = false
    }
}
