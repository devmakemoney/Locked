//
//  SchedulesView.swift
//  Créneau
//
//  The whole app on one screen: the dial for now, the grid for the week, the
//  groups underneath.
//
//  Not a plain List: the project this was forked from committed to a full
//  coloured surface, and a settings-style list makes a schedule feel like
//  paperwork. Here the dial carries the screen and everything else is a quiet
//  card — same idea, different execution.
//

import SwiftUI
import UIKit

struct SchedulesView: View {
    @StateObject private var store = ScheduleStore()
    @StateObject private var nfcReader = NFCReader()

    @State private var editingGroup: BlockGroup?
    @State private var isCreating = false
    @State private var creatingForDay: Int?
    @State private var showWrongTag = false
    @State private var showTagWritten = false
    @State private var tagWriteSucceeded = false
    @State private var now = Date()
    @State private var didCopyDiagnostic = false

    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            background
            content
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isCreating, onDismiss: { creatingForDay = nil }) {
            GroupEditorView(store: store, existing: nil, initialDay: creatingForDay)
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorView(store: store, existing: group, initialDay: nil)
        }
        .alert("Mauvaise carte", isPresented: $showWrongTag) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Ce tag ne porte pas le texte attendu.")
        }
        .alert(tagWriteSucceeded ? "Carte prête" : "Échec", isPresented: $showTagWritten) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(tagWriteSucceeded
                 ? "Garde-la hors de portée : c'est elle qui ouvre les blocages."
                 : "L'écriture a échoué. Réessaie en gardant le tag contre le haut du téléphone.")
        }
        .onReceive(clock) { tick in
            now = tick
            store.refreshState()
        }
        .onAppear { store.refreshState() }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color.groundTop, Color.ground],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if !store.isAuthorized { authorizationCard }
                dialCard
                if store.overrideUntil != nil { overrideCard }
                if !store.groups.isEmpty { weekCard }
                groupsCard
                settingsCard
                diagnosticsCard
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Créneau")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(dateLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ground)
                    .frame(width: 36, height: 36)
                    .background(Color.amber)
                    .clipShape(Circle())
            }
        }
        .padding(.top, 6)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: now).capitalized
    }

    // MARK: - Dial

    private var dialCard: some View {
        VStack(spacing: 14) {
            DayDialView(
                groups: store.groups,
                activeGroupIDs: store.activeGroupIDs,
                now: now,
                nextEvent: store.nextEvent
            )

            if !store.activeGroupIDs.isEmpty && store.overrideUntil == nil {
                Button(action: scanToUnlock) {
                    Label("Débloquer avec la carte", systemImage: "wave.3.right")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.amber)
                        .foregroundStyle(Color.ground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .card()
    }

    // MARK: - Cards

    private var authorizationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Autorisation manquante", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.amber)
            Text("Sans l'accès Temps d'écran, aucune app ne peut être bloquée.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Autoriser") {
                Task { await store.requestAuthorization() }
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.amber)
            .foregroundStyle(Color.ground)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var overrideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Déblocage actif")
                        .font(.subheadline.weight(.semibold))
                    if let remaining = store.overrideRemainingLabel {
                        Text("il reste \(remaining)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Button("Re-verrouiller") { store.cancelOverride() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.amber)
            }

            // iOS only checks the shield when an app is launched. An app left
            // open during the unlock stays usable after the re-lock, which
            // looks exactly like the re-lock doing nothing.
            Text("Ferme d'abord l'app débloquée : iOS ne repose pas le blocage sur une app restée ouverte.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("La semaine")
            WeekGridView(
                groups: store.groups,
                activeGroupIDs: store.activeGroupIDs,
                onSelectGroup: { editingGroup = $0 },
                onSelectDay: { day in
                    creatingForDay = day
                    isCreating = true
                }
            )
        }
        .card()
    }

    private var groupsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Groupes")

            if store.groups.isEmpty {
                Text("Aucun groupe. Touche le + en haut pour en créer un.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                    GroupRow(
                        group: group,
                        blockedCount: store.blockedCount(for: group.id),
                        isActive: store.activeGroupIDs.contains(group.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingGroup = group }

                    if index < store.groups.count - 1 {
                        Divider().overlay(Color.cardBorder)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Réglages")

            HStack {
                Text("Durée du déblocage")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $store.overrideMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 h").tag(60)
                    Text("2 h").tag(120)
                }
                .labelsHidden()
                .tint(Color.amber)
            }

            Divider().overlay(Color.cardBorder)

            Button(action: writeTag) {
                Label("Écrire ma carte NFC", systemImage: "wave.3.right.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Temporary, and deliberately ugly: the shield is not coming back after a
    /// manual re-lock and there is no console on a phone that is not plugged
    /// into Xcode. This says what we asked the store for and what it answered.
    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Diagnostic")

            Text(store.diagnosticReport)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIPasteboard.general.string = store.diagnosticReport
                didCopyDiagnostic = true
            } label: {
                Label(didCopyDiagnostic ? "Copié" : "Copier", systemImage: "doc.on.doc")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Actions

    private func scanToUnlock() {
        let expected = SharedStore.nfcTagPayload
        nfcReader.scan { payload in
            if payload == expected {
                store.unlockWithTag()
            } else {
                showWrongTag = true
            }
        }
    }

    private func writeTag() {
        nfcReader.write(SharedStore.nfcTagPayload) { success in
            tagWriteSucceeded = success
            showTagWritten = true
        }
    }
}

// MARK: - Row

struct GroupRow: View {
    let group: BlockGroup
    let blockedCount: Int
    let isActive: Bool

    /// Enough to recognise the group without opening it.
    private var windowsLabel: String {
        guard !group.windows.isEmpty else { return "Aucune plage" }
        let ranges = group.windows
            .sorted { $0.startMinutes < $1.startMinutes }
            .prefix(2)
            .map(\.rangeLabel)
            .joined(separator: ", ")
        return group.windows.count > 2 ? "\(group.windows.count) plages · \(ranges)…" : ranges
    }

    private var contentLabel: String {
        let sites = group.webDomains.count
        if blockedCount == 0 && sites == 0 { return "Rien de sélectionné" }
        var parts: [String] = []
        if blockedCount > 0 { parts.append("\(blockedCount) app\(blockedCount > 1 ? "s" : "")") }
        if sites > 0 { parts.append("\(sites) site\(sites > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    private var isEmpty: Bool {
        blockedCount == 0 && group.webDomains.isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? Color.amber : Color.cardBorder)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.body.weight(.medium))
                Text(windowsLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(contentLabel)
                    .font(.caption2)
                    .foregroundStyle(isEmpty ? Color.amber : Color.slate)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
