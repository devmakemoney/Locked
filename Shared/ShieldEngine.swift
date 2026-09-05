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
        var blockedDomains = Set<WebDomain>()

        for group in groups {
            if let selection = selections[group.id] {
                blockedApps.formUnion(selection.applicationTokens)
                blockedCategories.formUnion(selection.categoryTokens)
            }
            for domain in group.webDomains {
                blockedDomains.insert(WebDomain(domain: domain))
            }
        }

        store.shield.applications = blockedApps.isEmpty ? nil : blockedApps
        store.shield.applicationCategories = blockedCategories.isEmpty
            ? ShieldSettings.ActivityCategoryPolicy.none
            : .specific(blockedCategories)

        // Websites go through the content filter rather than the shield: the
        // shield only accepts tokens handed out by the picker, which cannot
        // produce an arbitrary domain the user typed.
        store.webContent.blockedByFilter = blockedDomains.isEmpty
            ? nil
            : .specific(blockedDomains)

        // Locked cannot be deleted while it is enforcing something.
        store.application.denyAppRemoval = true

        record(
            intent: "\(groups.count) groupe(s) · \(blockedApps.count) app · "
                + "\(blockedCategories.count) cat · \(blockedDomains.count) site",
            at: date
        )
        return groups
    }

    static func clear() {
        store.shield.applications = nil
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.webContent.blockedByFilter = nil
        store.application.denyAppRemoval = false
        record(intent: "rien à bloquer", at: Date())
    }

    // MARK: - Diagnostics

    /// What the store answers when we read it straight back after writing.
    ///
    /// The point of reading back: a block that "does nothing" is either a store
    /// we never wrote (intent empty) or one iOS refused (intent full, readback
    /// empty). Guessing between those from the outside is impossible, and the
    /// console is not reachable on a device that is not plugged into Xcode.
    static var storeReadback: String {
        var parts: [String] = []
        parts.append("apps \(store.shield.applications?.count.description ?? "nil")")
        parts.append("cat " + categoriesLabel)
        parts.append("sites " + (store.webContent.blockedByFilter != nil ? "actif" : "nil"))
        parts.append("denyAppRemoval " + (store.application.denyAppRemoval == true ? "oui" : "non"))
        return parts.joined(separator: " · ")
    }

    private static var categoriesLabel: String {
        guard let policy = store.shield.applicationCategories else { return "nil" }
        switch policy {
        case .none: return "aucune"
        case .all: return "toutes"
        case .specific(let categories, _): return "\(categories.count)"
        @unknown default: return "?"
        }
    }

    /// Both processes write here, so the app can show what the extension did
    /// while it was not running.
    private static func record(intent: String, at date: Date) {
        let stamp = DateFormatter.diagnosticClock.string(from: date)
        let line = "\(stamp) — voulu : \(intent)\n\(stamp) — store : \(storeReadback)"
        SharedStore.lastShieldLog = line
        NSLog("[Créneau] \(line.replacingOccurrences(of: "\n", with: " | "))")
    }
}

private extension DateFormatter {
    static let diagnosticClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
