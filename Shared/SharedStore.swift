//
//  SharedStore.swift
//  Locked — shared between the app and the LockedMonitor extension
//
//  The app writes, the extension reads. Both go through the App Group so the
//  extension can rebuild the shield without the app ever being launched.
//

import Foundation
import FamilyControls

enum SharedStore {
    static let appGroup = "group.com.timothee.locked"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private enum Key {
        static let groups = "blockGroups"
        static let legacyRules = "scheduleRules"
        static let selections = "ruleSelections"
        static let overrideUntil = "nfcOverrideUntil"
        static let overrideGroups = "nfcOverrideGroupIDs"
        static let nfcTag = "nfcTagPayload"
        static let lastShieldLog = "lastShieldLog"
    }

    // MARK: - Block groups

    static var groups: [BlockGroup] {
        get {
            migrateLegacyRulesIfNeeded()
            guard let data = defaults.data(forKey: Key.groups),
                  let decoded = try? JSONDecoder().decode([BlockGroup].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: Key.groups)
            }
        }
    }

    /// Rules used to be one window each, with the app selection stored under
    /// the rule id. Turn every old rule into a one-window group, keeping the id
    /// so its selection follows.
    private static func migrateLegacyRulesIfNeeded() {
        guard defaults.data(forKey: Key.groups) == nil,
              let data = defaults.data(forKey: Key.legacyRules),
              let legacy = try? JSONDecoder().decode([LegacyRule].self, from: data)
        else { return }

        let migrated = legacy.map { rule in
            BlockGroup(
                id: rule.id,
                name: rule.name,
                windows: [TimeWindow(weekdays: rule.weekdays,
                                     startMinutes: rule.startMinutes,
                                     endMinutes: rule.endMinutes)],
                isEnabled: rule.isEnabled
            )
        }
        if let encoded = try? JSONEncoder().encode(migrated) {
            defaults.set(encoded, forKey: Key.groups)
            defaults.removeObject(forKey: Key.legacyRules)
            NSLog("[Créneau] migrated \(migrated.count) rules to groups")
        }
    }

    private struct LegacyRule: Codable {
        let id: UUID
        let name: String
        let weekdays: Set<Int>
        let startMinutes: Int
        let endMinutes: Int
        let isEnabled: Bool
    }

    /// Which apps each group blocks, keyed by group id.
    ///
    /// Kept beside the rules rather than inside them so ScheduleRule stays pure
    /// Foundation — that is what lets the date logic be tested outside iOS.
    static var selections: [UUID: FamilyActivitySelection] {
        get {
            guard let data = defaults.data(forKey: Key.selections),
                  let decoded = try? JSONDecoder().decode([UUID: FamilyActivitySelection].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: Key.selections)
            }
        }
    }

    static func selection(for groupID: UUID) -> FamilyActivitySelection {
        selections[groupID] ?? FamilyActivitySelection()
    }

    static func setSelection(_ selection: FamilyActivitySelection, for groupID: UUID) {
        var all = selections
        all[groupID] = selection
        selections = all
    }

    static func removeSelection(for groupID: UUID) {
        var all = selections
        all.removeValue(forKey: groupID)
        selections = all
    }

    // MARK: - NFC override

    /// While this date is in the future, the groups listed in
    /// `overriddenGroupIDs` are suspended. Set only after a scan matched the tag.
    static var overrideUntil: Date? {
        get { defaults.object(forKey: Key.overrideUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.overrideUntil) }
    }

    static var overriddenGroupIDs: Set<UUID> {
        get {
            let raw = defaults.stringArray(forKey: Key.overrideGroups) ?? []
            return Set(raw.compactMap(UUID.init(uuidString:)))
        }
        set { defaults.set(newValue.map(\.uuidString), forKey: Key.overrideGroups) }
    }

    static var isOverrideActive: Bool {
        guard let until = overrideUntil else { return false }
        return until > Date()
    }

    static func startOverride(minutes: Int, groupIDs: Set<UUID>) {
        overrideUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        overriddenGroupIDs = groupIDs
    }

    static func clearOverride() {
        defaults.removeObject(forKey: Key.overrideUntil)
        defaults.removeObject(forKey: Key.overrideGroups)
    }

    // MARK: - Diagnostics

    /// Last thing ShieldEngine pushed, and what the store answered. Written by
    /// whichever process ran last, so the app can show what the monitor
    /// extension did while the app was closed.
    static var lastShieldLog: String? {
        get { defaults.string(forKey: Key.lastShieldLog) }
        set { defaults.set(newValue, forKey: Key.lastShieldLog) }
    }

    // MARK: - NFC tag

    static let defaultTagPhrase = "LOCKED-IS-GREAT"

    /// Text written on the tag. A scan must match it exactly to unlock.
    static var nfcTagPayload: String {
        get { defaults.string(forKey: Key.nfcTag) ?? defaultTagPhrase }
        set { defaults.set(newValue, forKey: Key.nfcTag) }
    }
}
