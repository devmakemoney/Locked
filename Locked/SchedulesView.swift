//
//  SchedulesView.swift
//  Locked
//
//  The schedule tab: what is blocked right now, the rules, and the NFC unlock.
//

import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject private var profileManager: ProfileManager
    @StateObject private var store = ScheduleStore()
    @StateObject private var nfcReader = NFCReader()

    @State private var editingRule: ScheduleRule?
    @State private var isCreating = false
    @State private var showWrongTag = false
    @State private var showNoTagPaired = false
    @State private var showSeedConfirm = false
    @State private var tick = Date()

    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if store.overrideUntil != nil { overrideSection }
                rulesSection
                settingsSection
            }
            .navigationTitle("Plannings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isCreating) {
                ScheduleEditorView(store: store, existing: nil)
                    .environmentObject(profileManager)
            }
            .sheet(item: $editingRule) { rule in
                ScheduleEditorView(store: store, existing: rule)
                    .environmentObject(profileManager)
            }
            .alert("Mauvaise carte", isPresented: $showWrongTag) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Ce tag n'est pas celui associé à Locked.")
            }
            .alert("Aucune carte associée", isPresented: $showNoTagPaired) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Crée d'abord ta carte NFC depuis l'onglet Verrou, sinon le déblocage est impossible.")
            }
            .confirmationDialog("Charger la routine ?", isPresented: $showSeedConfirm, titleVisibility: .visible) {
                Button("Créer les 3 règles") { seedRoutine() }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("Travail bloqué hors 8h–10h et 13h15–17h45, loisir écran ouvert seulement de 18h40 à 20h.")
            }
            .onReceive(clock) { now in
                tick = now
                store.refreshState()
            }
            .onAppear { store.refreshState() }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: store.activeRuleIDs.isEmpty ? "lock.open" : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(store.activeRuleIDs.isEmpty ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.activeRuleIDs.isEmpty ? "Rien n'est bloqué" : "Blocage en cours")
                        .font(.headline)
                    Text(activeSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if !store.activeRuleIDs.isEmpty && store.overrideUntil == nil {
                Button {
                    scanToUnlock()
                } label: {
                    Label("Débloquer avec la carte NFC", systemImage: "wave.3.right")
                }
            }
        }
    }

    private var activeSummary: String {
        guard !store.activeRuleIDs.isEmpty else {
            return store.isEngineEnabled ? "Aucune règle active à cette heure." : "Moteur désactivé."
        }
        let names = store.rules
            .filter { store.activeRuleIDs.contains($0.id) }
            .map(\.name)
        return names.joined(separator: ", ")
    }

    private var overrideSection: some View {
        Section {
            HStack {
                Label("Déblocage actif", systemImage: "hourglass")
                Spacer()
                if let remaining = store.overrideRemainingLabel {
                    Text(remaining)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Button("Re-verrouiller maintenant", role: .destructive) {
                store.cancelOverride()
            }
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        Section {
            if store.rules.isEmpty {
                Button {
                    showSeedConfirm = true
                } label: {
                    Label("Charger ma routine", systemImage: "wand.and.stars")
                }
                Text("Aucune règle. Ajoute-en une avec +, ou charge la routine pré-remplie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.rules) { rule in
                    RuleRow(
                        rule: rule,
                        profileName: profileManager.profiles.first { $0.id == rule.profileID }?.name,
                        isActive: store.activeRuleIDs.contains(rule.id),
                        onToggle: { store.toggle(rule, enabled: $0) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editingRule = rule }
                }
                .onDelete { indexSet in
                    indexSet.map { store.rules[$0] }.forEach(store.delete)
                }
            }
        } header: {
            Text("Règles")
        } footer: {
            Text("Chaque règle a ses propres jours et horaires. Une plage qui finit avant son début se termine le lendemain matin.")
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        Section("Réglages") {
            Toggle("Moteur de planification", isOn: Binding(
                get: { store.isEngineEnabled },
                set: { store.setEngineEnabled($0) }
            ))

            Picker("Durée du déblocage NFC", selection: $store.overrideMinutes) {
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 h").tag(60)
                Text("2 h").tag(120)
            }

            if !store.rules.isEmpty {
                Button {
                    showSeedConfirm = true
                } label: {
                    Label("Ajouter ma routine", systemImage: "wand.and.stars")
                }
            }

            Button {
                store.refreshState()
                ScheduleManager.refresh()
            } label: {
                Label("Recalculer maintenant", systemImage: "arrow.clockwise")
            }
        }
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

    private func seedRoutine() {
        let work = ensureProfile(named: "Travail", icon: "briefcase.fill")
        let leisure = ensureProfile(named: "Loisir", icon: "iphone")
        store.seedRoutine(workProfileID: work, leisureProfileID: leisure)
    }

    private func ensureProfile(named name: String, icon: String) -> UUID {
        if let existing = profileManager.profiles.first(where: { $0.name == name }) {
            return existing.id
        }
        let profile = Profile(name: name, appTokens: [], categoryTokens: [], icon: icon)
        profileManager.addProfile(newProfile: profile)
        return profile.id
    }
}

// MARK: - Row

struct RuleRow: View {
    let rule: ScheduleRule
    let profileName: String?
    let isActive: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(isActive ? Color.red : Color.secondary.opacity(0.3))
                .frame(width: 4)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.body.weight(.medium))
                Text("\(rule.rangeLabel) · \(rule.weekdaysLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let profileName {
                    Text(profileName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: onToggle
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
