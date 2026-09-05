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

    /// The next moment any group starts or stops blocking, and which one.
    ///
    /// Not "is anything blocked" — with a Travail group and a Loisir group the
    /// answer is almost always yes, which tells you nothing. What you want to
    /// know is which door opens next, and when.
    ///
    /// Walked minute by minute rather than by comparing window boundaries:
    /// 1440 cheap checks, and it cannot get the midnight-crossing or
    /// overlapping-window cases wrong the way boundary maths would.
    struct NextEvent {
        let minutes: Int
        let groupName: String
        /// true when the group stops blocking.
        let isOpening: Bool
    }

    var nextEvent: NextEvent? {
        let calendar = Calendar.current
        let start = Date()
        let all = SharedStore.groups
        guard !all.isEmpty else { return nil }

        var previous = Set(all.filter { $0.isActive(at: start, calendar: calendar) }.map(\.id))

        for offset in 1...1440 {
            guard let future = calendar.date(byAdding: .minute, value: offset, to: start) else { break }
            let current = Set(all.filter { $0.isActive(at: future, calendar: calendar) }.map(\.id))
            if current == previous { continue }

            if let opened = previous.subtracting(current).first,
               let group = all.first(where: { $0.id == opened }) {
                return NextEvent(minutes: offset, groupName: group.name, isOpening: true)
            }
            if let closed = current.subtracting(previous).first,
               let group = all.first(where: { $0.id == closed }) {
                return NextEvent(minutes: offset, groupName: group.name, isOpening: false)
            }
            previous = current
        }
        return nil
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
        ScheduleManager.stopOverrideWindow()
        applyAndReload()
    }

    // MARK: - Diagnostics

    /// Everything needed to tell "we never wrote the store" apart from "iOS
    /// refused what we wrote", in a form Tim can read on the device and paste
    /// back. The console is not an option on a phone that is not plugged in.
    var diagnosticReport: String {
        var lines: [String] = []
        lines.append("Créneau — \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))")
        lines.append("Temps d'écran : \(isAuthorized ? "autorisé" : "REFUSÉ")")

        let active = Set(ShieldEngine.activeGroups().map(\.id))
        if SharedStore.groups.isEmpty {
            lines.append("Aucun groupe")
        }
        for group in SharedStore.groups {
            let selection = SharedStore.selection(for: group.id)
            lines.append(
                "• \(group.name) — \(group.isEnabled ? "activé" : "désactivé"), "
                + "\(active.contains(group.id) ? "BLOQUE" : "ouvert") · "
                + "\(selection.applicationTokens.count) app, "
                + "\(selection.categoryTokens.count) cat, "
                + "\(group.webDomains.count) site"
            )
        }

        if let until = SharedStore.overrideUntil {
            lines.append("Override jusqu'à \(DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .medium))"
                         + " (\(SharedStore.isOverrideActive ? "actif" : "expiré"))")
        } else {
            lines.append("Override : aucun")
        }

        lines.append("Store maintenant : \(ShieldEngine.storeReadback)")
        lines.append(SharedStore.lastShieldLog ?? "Aucun apply enregistré")
        return lines.joined(separator: "\n")
    }

    var overrideRemainingLabel: String? {
        guard let until = overrideUntil, until > Date() else { return nil }
        let seconds = Int(until.timeIntervalSinceNow)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
