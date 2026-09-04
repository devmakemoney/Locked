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

    /// Rules that should be blocking at `date`, override taken into account.
    static func activeRules(at date: Date = Date()) -> [ScheduleRule] {
        guard SharedStore.scheduleEnabled else { return [] }

        let overridden = SharedStore.isOverrideActive ? SharedStore.overriddenRuleIDs : []
        return SharedStore.rules.filter { rule in
            rule.isActive(at: date) && !overridden.contains(rule.id)
        }
    }

    /// Recompute and push the shield. Safe to call from anywhere, any number of
    /// times — it is idempotent.
    @discardableResult
    static func apply(at date: Date = Date()) -> [ScheduleRule] {
        if let until = SharedStore.overrideUntil, until <= date {
            SharedStore.clearOverride()
        }

        let rules = activeRules(at: date)
        let profiles = SharedStore.profiles

        guard !rules.isEmpty else {
            clear()
            return []
        }

        var blockedApps = Set<ApplicationToken>()
        var blockedCategories = Set<ActivityCategoryToken>()
        var allowListTokens: Set<ApplicationToken>?

        for rule in rules {
            guard let profile = profiles.first(where: { $0.id == rule.profileID }) else { continue }
            if profile.isAllowListMode {
                // Intersect: with two allow-lists active, only apps allowed by
                // both stay reachable — the stricter reading.
                allowListTokens = allowListTokens.map { $0.intersection(profile.appTokens) } ?? profile.appTokens
            } else {
                blockedApps.formUnion(profile.appTokens)
                blockedCategories.formUnion(profile.categoryTokens)
            }
        }

        if let allowed = allowListTokens {
            store.shield.applications = nil
            store.shield.applicationCategories = allowed.isEmpty ? .all() : .all(except: allowed)
        } else {
            store.shield.applications = blockedApps.isEmpty ? nil : blockedApps
            store.shield.applicationCategories = blockedCategories.isEmpty
                ? ShieldSettings.ActivityCategoryPolicy.none
                : .specific(blockedCategories)
        }

        // Cannot delete Locked while it is enforcing something.
        store.application.denyAppRemoval = true
        return rules
    }

    static func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.application.denyAppRemoval = false
    }
}
