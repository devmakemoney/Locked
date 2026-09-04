//
//  SharedStore.swift
//  Locked — shared between the app and the LockedMonitor extension
//
//  The app writes, the extension reads. Both go through the App Group so the
//  extension can rebuild the shield without the app ever being launched.
//

import Foundation
import FamilyControls
import ManagedSettings

enum SharedStore {
    static let appGroup = "group.com.timothee.locked"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private enum Key {
        static let profiles = "savedProfiles"
        static let currentProfile = "currentProfileId"
        static let rules = "scheduleRules"
        static let overrideUntil = "nfcOverrideUntil"
        static let overrideRules = "nfcOverrideRuleIDs"
        static let nfcTag = "nfcTagPayload"
        static let scheduleEnabled = "scheduleEngineEnabled"
        static let migrated = "didMigrateToAppGroup"
    }

    // MARK: - Migration

    /// One-shot copy of the original app's UserDefaults.standard data into the
    /// App Group. Runs before the first read so nothing is lost on upgrade.
    static func migrateIfNeeded() {
        guard !defaults.bool(forKey: Key.migrated) else { return }
        let standard = UserDefaults.standard
        for key in [Key.profiles, Key.currentProfile, Key.nfcTag] {
            if defaults.object(forKey: key) == nil, let value = standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: Key.migrated)
    }

    // MARK: - Profiles

    static var profiles: [Profile] {
        get {
            guard let data = defaults.data(forKey: Key.profiles),
                  let decoded = try? JSONDecoder().decode([Profile].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: Key.profiles)
            }
        }
    }

    static func profile(with id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    static var currentProfileID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Key.currentProfile) else { return nil }
            return UUID(uuidString: raw)
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.currentProfile) }
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

    /// Master switch. Off means the schedule engine never shields anything.
    static var scheduleEnabled: Bool {
        get { defaults.object(forKey: Key.scheduleEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.scheduleEnabled) }
    }

    // MARK: - NFC override

    /// While this date is in the future, the rules listed in `overriddenRuleIDs`
    /// are suspended. Set only after a successful NFC scan.
    static var overrideUntil: Date? {
        get { defaults.object(forKey: Key.overrideUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.overrideUntil) }
    }

    static var overriddenRuleIDs: Set<UUID> {
        get {
            let raw = defaults.stringArray(forKey: Key.overrideRules) ?? []
            return Set(raw.compactMap(UUID.init(uuidString:)))
        }
        set {
            defaults.set(newValue.map(\.uuidString), forKey: Key.overrideRules)
        }
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

    /// Text the original app writes on the tag. Kept as the fallback so a tag
    /// created during onboarding keeps working.
    static let defaultTagPhrase = "LOCKED-IS-GREAT"

    /// Payload written on the user's own tag. Unlocking requires a scan whose
    /// text matches this exactly.
    static var nfcTagPayload: String {
        get { defaults.string(forKey: Key.nfcTag) ?? defaultTagPhrase }
        set { defaults.set(newValue, forKey: Key.nfcTag) }
    }
}
