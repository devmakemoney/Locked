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
        static let rules = "scheduleRules"
        static let selections = "ruleSelections"
        static let overrideUntil = "nfcOverrideUntil"
        static let overrideRules = "nfcOverrideRuleIDs"
        static let nfcTag = "nfcTagPayload"
        static let scheduleEnabled = "scheduleEngineEnabled"
    }

    // MARK: - Schedule rules

    static var rules: [ScheduleRule] {
        get {
            guard let data = defaults.data(forKey: Key.rules),
                  let decoded = try? JSONDecoder().decode([ScheduleRule].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: Key.rules)
            }
        }
    }

    /// Which apps each rule blocks, keyed by rule id.
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

    static func selection(for ruleID: UUID) -> FamilyActivitySelection {
        selections[ruleID] ?? FamilyActivitySelection()
    }

    static func setSelection(_ selection: FamilyActivitySelection, for ruleID: UUID) {
        var all = selections
        all[ruleID] = selection
        selections = all
    }

    static func removeSelection(for ruleID: UUID) {
        var all = selections
        all.removeValue(forKey: ruleID)
        selections = all
    }

    /// Master switch. Off means nothing is ever shielded.
    static var scheduleEnabled: Bool {
        get { defaults.object(forKey: Key.scheduleEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.scheduleEnabled) }
    }

    // MARK: - NFC override

    /// While this date is in the future, the rules listed in `overriddenRuleIDs`
    /// are suspended. Set only after a scan matched the paired tag.
    static var overrideUntil: Date? {
        get { defaults.object(forKey: Key.overrideUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.overrideUntil) }
    }

    static var overriddenRuleIDs: Set<UUID> {
        get {
            let raw = defaults.stringArray(forKey: Key.overrideRules) ?? []
            return Set(raw.compactMap(UUID.init(uuidString:)))
        }
        set { defaults.set(newValue.map(\.uuidString), forKey: Key.overrideRules) }
    }

    static var isOverrideActive: Bool {
        guard let until = overrideUntil else { return false }
        return until > Date()
    }

    static func startOverride(minutes: Int, ruleIDs: Set<UUID>) {
        overrideUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        overriddenRuleIDs = ruleIDs
    }

    static func clearOverride() {
        defaults.removeObject(forKey: Key.overrideUntil)
        defaults.removeObject(forKey: Key.overrideRules)
    }

    // MARK: - NFC tag

    static let defaultTagPhrase = "LOCKED-IS-GREAT"

    /// Text written on the tag. A scan must match it exactly to unlock.
    static var nfcTagPayload: String {
        get { defaults.string(forKey: Key.nfcTag) ?? defaultTagPhrase }
        set { defaults.set(newValue, forKey: Key.nfcTag) }
    }
}
