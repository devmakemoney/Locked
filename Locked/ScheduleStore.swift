//
//  ScheduleStore.swift
//  Locked
//
//  Observable wrapper around SharedStore for the UI. Every write goes straight
//  to the App Group and re-arms the DeviceActivity windows.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var rules: [ScheduleRule] = []
    @Published var isEngineEnabled: Bool = true
    @Published var activeRuleIDs: Set<UUID> = []
    @Published var overrideUntil: Date?

    /// How long an NFC scan suspends the active rules. iOS refuses
    /// DeviceActivity windows under 15 minutes, so that is the floor.
    @AppStorage("nfcOverrideMinutes") var overrideMinutes: Int = 15

    init() {
        SharedStore.migrateIfNeeded()
        reload()
    }

    func reload() {
        rules = SharedStore.rules.sorted { $0.startMinutes < $1.startMinutes }
        isEngineEnabled = SharedStore.scheduleEnabled
        overrideUntil = SharedStore.isOverrideActive ? SharedStore.overrideUntil : nil
        activeRuleIDs = Set(ShieldEngine.activeRules().map(\.id))
    }

    func refreshState() {
        ShieldEngine.apply()
        reload()
    }

    // MARK: - Mutations

    func save(_ rule: ScheduleRule) {
        var all = SharedStore.rules
        if let index = all.firstIndex(where: { $0.id == rule.id }) {
            all[index] = rule
        } else {
            all.append(rule)
        }
        SharedStore.rules = all
        applyAndReload()
    }

    func delete(_ rule: ScheduleRule) {
        SharedStore.rules = SharedStore.rules.filter { $0.id != rule.id }
        applyAndReload()
    }

    func toggle(_ rule: ScheduleRule, enabled: Bool) {
        var copy = rule
        copy.isEnabled = enabled
        save(copy)
    }

    func setEngineEnabled(_ enabled: Bool) {
        SharedStore.scheduleEnabled = enabled
        applyAndReload()
    }

    private func applyAndReload() {
        ScheduleManager.refresh()
        reload()
    }

    // MARK: - NFC unlock

    /// Called only after a scan matched the paired tag.
    func unlockWithTag() {
        let active = ShieldEngine.activeRules().map(\.id)
        guard !active.isEmpty else { return }
        SharedStore.startOverride(minutes: overrideMinutes, ruleIDs: Set(active))
        ScheduleManager.armOverrideEnd(at: SharedStore.overrideUntil ?? Date())
        ShieldEngine.apply()
        reload()
    }

    func cancelOverride() {
        SharedStore.clearOverride()
        applyAndReload()
    }

    var overrideRemainingLabel: String? {
        guard let until = overrideUntil, until > Date() else { return nil }
        let seconds = Int(until.timeIntervalSinceNow)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Tim's routine

    /// Seeds the three rules matching the printed wall schedule.
    /// Work is blocked outside the two deep-work windows; screen leisure is
    /// only open between 18h40 and 20h00.
    func seedRoutine(workProfileID: UUID, leisureProfileID: UUID) {
        let everyday: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]

        let seeded = [
            ScheduleRule(
                name: "Travail — soir et nuit",
                profileID: workProfileID,
                weekdays: everyday,
                startMinutes: 17 * 60 + 45,
                endMinutes: 8 * 60
            ),
            ScheduleRule(
                name: "Travail — matinée dehors",
                profileID: workProfileID,
                weekdays: weekdays,
                startMinutes: 10 * 60,
                endMinutes: 13 * 60 + 15
            ),
            ScheduleRule(
                name: "Loisir écran",
                profileID: leisureProfileID,
                weekdays: everyday,
                startMinutes: 20 * 60,
                endMinutes: 18 * 60 + 40
            ),
        ]

        SharedStore.rules = SharedStore.rules + seeded
        applyAndReload()
    }
}
