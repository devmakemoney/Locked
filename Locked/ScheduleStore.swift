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
    @Published var groups: [BlockGroup] = []
    @Published var isEngineEnabled: Bool = true
    @Published var activeGroupIDs: Set<UUID> = []
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
        groups = SharedStore.groups.sorted { $0.earliestStart < $1.earliestStart }
        isEngineEnabled = SharedStore.scheduleEnabled
        overrideUntil = SharedStore.isOverrideActive ? SharedStore.overrideUntil : nil
        activeGroupIDs = Set(ShieldEngine.activeGroups().map(\.id))
        refreshAuthorization()
    }

    func refreshState() {
        ShieldEngine.apply()
        reload()
    }

    func selection(for groupID: UUID) -> FamilyActivitySelection {
        SharedStore.selection(for: groupID)
    }

    /// How many apps and categories a group blocks, for the list row.
    func blockedCount(for groupID: UUID) -> Int {
        let selection = SharedStore.selection(for: groupID)
        return selection.applicationTokens.count + selection.categoryTokens.count
    }

    // MARK: - Mutations

    func save(_ group: BlockGroup, selection: FamilyActivitySelection) {
        var all = SharedStore.groups
        if let index = all.firstIndex(where: { $0.id == group.id }) {
            all[index] = group
        } else {
            all.append(group)
        }
        SharedStore.groups = all
        SharedStore.setSelection(selection, for: group.id)
        applyAndReload()
    }

    func delete(_ group: BlockGroup) {
        SharedStore.groups = SharedStore.groups.filter { $0.id != group.id }
        SharedStore.removeSelection(for: group.id)
        applyAndReload()
    }

    func toggle(_ group: BlockGroup, enabled: Bool) {
        var copy = group
        copy.isEnabled = enabled
        var all = SharedStore.groups
        if let index = all.firstIndex(where: { $0.id == group.id }) {
            all[index] = copy
            SharedStore.groups = all
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
        let active = ShieldEngine.activeGroups().map(\.id)
        guard !active.isEmpty else { return }
        SharedStore.startOverride(minutes: overrideMinutes, groupIDs: Set(active))
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
}
