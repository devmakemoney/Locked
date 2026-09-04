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
import FamilyControls

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var rules: [ScheduleRule] = []
    @Published var isEngineEnabled: Bool = true
    @Published var activeRuleIDs: Set<UUID> = []
    @Published var overrideUntil: Date?
    @Published var isAuthorized: Bool = false

    /// How long an NFC scan suspends the active rules. iOS refuses
    /// DeviceActivity windows under 15 minutes, so that is the floor.
    @AppStorage("nfcOverrideMinutes") var overrideMinutes: Int = 15

    init() {
        reload()
        Task { await requestAuthorization() }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            NSLog("[Locked] authorization refused: \(error.localizedDescription)")
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        }
    }

    func refreshAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // MARK: - Reading

    func reload() {
        rules = SharedStore.rules.sorted { $0.startMinutes < $1.startMinutes }
        isEngineEnabled = SharedStore.scheduleEnabled
        overrideUntil = SharedStore.isOverrideActive ? SharedStore.overrideUntil : nil
        activeRuleIDs = Set(ShieldEngine.activeRules().map(\.id))
        refreshAuthorization()
    }

    func refreshState() {
        ShieldEngine.apply()
        reload()
    }

    func selection(for ruleID: UUID) -> FamilyActivitySelection {
        SharedStore.selection(for: ruleID)
    }

    /// How many apps and categories a rule blocks, for the list row.
    func blockedCount(for ruleID: UUID) -> Int {
        let selection = SharedStore.selection(for: ruleID)
        return selection.applicationTokens.count + selection.categoryTokens.count
    }

    // MARK: - Mutations

    func save(_ rule: ScheduleRule, selection: FamilyActivitySelection) {
        var all = SharedStore.rules
        if let index = all.firstIndex(where: { $0.id == rule.id }) {
            all[index] = rule
        } else {
            all.append(rule)
        }
        SharedStore.rules = all
        SharedStore.setSelection(selection, for: rule.id)
        applyAndReload()
    }

    func delete(_ rule: ScheduleRule) {
        SharedStore.rules = SharedStore.rules.filter { $0.id != rule.id }
        SharedStore.removeSelection(for: rule.id)
        applyAndReload()
    }

    func toggle(_ rule: ScheduleRule, enabled: Bool) {
        var copy = rule
        copy.isEnabled = enabled
        var all = SharedStore.rules
        if let index = all.firstIndex(where: { $0.id == rule.id }) {
            all[index] = copy
            SharedStore.rules = all
        }
        applyAndReload()
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

    /// Seeds the three rules matching the printed wall schedule. Apps still
    /// have to be picked per rule afterwards.
    func seedRoutine() {
        let everyday: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]

        let seeded = [
            ScheduleRule(
                name: "Travail — soir et nuit",
                weekdays: everyday,
                startMinutes: 17 * 60 + 45,
                endMinutes: 8 * 60
            ),
            ScheduleRule(
                name: "Travail — matinée dehors",
                weekdays: weekdays,
                startMinutes: 10 * 60,
                endMinutes: 13 * 60 + 15
            ),
            ScheduleRule(
                name: "Loisir écran",
                weekdays: everyday,
                startMinutes: 20 * 60,
                endMinutes: 18 * 60 + 40
            ),
        ]

        SharedStore.rules = SharedStore.rules + seeded
        applyAndReload()
    }
}
