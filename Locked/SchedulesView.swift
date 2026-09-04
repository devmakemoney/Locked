//
//  SchedulesView.swift
//  Locked
//
//  The whole app: what is blocked right now, the rules, and the NFC unlock.
//

import SwiftUI

struct SchedulesView: View {
    @StateObject private var store = ScheduleStore()
    @StateObject private var nfcReader = NFCReader()

    @State private var editingRule: ScheduleRule?
    @State private var isCreating = false
    @State private var creatingForDay: Int?
    @State private var showWrongTag = false
    @State private var showSeedConfirm = false
    @State private var showTagWritten = false
    @State private var tagWriteSucceeded = false
    @State private var tick = Date()

    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                if !store.isAuthorized { authorizationSection }
                statusSection
                if store.overrideUntil != nil { overrideSection }
                if !store.rules.isEmpty { weekSection }
                rulesSection
                settingsSection
            }
            .navigationTitle("Créneau")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isCreating, onDismiss: { creatingForDay = nil }) {
                ScheduleEditorView(store: store, existing: nil, initialDay: creatingForDay)
            }
            .sheet(item: $editingRule) { rule in
                ScheduleEditorView(store: store, existing: rule, initialDay: nil)
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
            .confirmationDialog("Charger la routine ?", isPresented: $showSeedConfirm, titleVisibility: .visible) {
                Button("Créer les 3 règles") { store.seedRoutine() }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text("Travail bloqué hors 8h–10h et 13h15–17h45, loisir écran ouvert seulement de 18h40 à 20h. Les apps restent à choisir dans chaque règle.")
            }
            .onReceive(clock) { now in
                tick = now
                store.refreshState()
            }
            .onAppear { store.refreshState() }
        }
    }

    // MARK: - Authorization

    private var authorizationSection: some View {
        Section {
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
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: store.activeRuleIDs.isEmpty ? "lock.open" : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(store.activeRuleIDs.isEmpty ? Color.slate : Color.amber)
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
                    Label("Débloquer avec la carte", systemImage: "wave.3.right")
                }
            }
        }
    }

    private var activeSummary: String {
        guard !store.activeRuleIDs.isEmpty else {
            return store.isEngineEnabled ? "Aucune règle active à cette heure." : "Moteur désactivé."
        }
        return store.rules
            .filter { store.activeRuleIDs.contains($0.id) }
            .map(\.name)
            .joined(separator: ", ")
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

    // MARK: - Week

    private var weekSection: some View {
        Section {
            WeekGridView(
                rules: store.rules,
                activeRuleIDs: store.activeRuleIDs,
                onSelectRule: { editingRule = $0 },
                onSelectDay: { day in
                    creatingForDay = day
                    isCreating = true
                }
            )
            .padding(.vertical, 4)
        } header: {
            Text("Ma semaine")
        } footer: {
            Text("Tape une plage pour la modifier, une zone vide pour ajouter une plage ce jour-là.")
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
                        blockedCount: store.blockedCount(for: rule.id),
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
            Text("Chaque règle a ses propres apps, jours et horaires. Une plage qui finit avant son début se termine le lendemain matin.")
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        Section("Réglages") {
            Toggle("Moteur de planification", isOn: Binding(
                get: { store.isEngineEnabled },
                set: { store.setEngineEnabled($0) }
            ))
            .tint(Color.amber)

            Picker("Durée du déblocage", selection: $store.overrideMinutes) {
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 h").tag(60)
                Text("2 h").tag(120)
            }

            Button {
                writeTag()
            } label: {
                Label("Écrire ma carte NFC", systemImage: "wave.3.right.circle")
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

    private func writeTag() {
        nfcReader.write(SharedStore.nfcTagPayload) { success in
            tagWriteSucceeded = success
            showTagWritten = true
        }
    }
}

// MARK: - Row

struct RuleRow: View {
    let rule: ScheduleRule
    let blockedCount: Int
    let isActive: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(isActive ? Color.amber : Color.secondary.opacity(0.25))
                .frame(width: 4)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.body.weight(.medium))
                Text("\(rule.rangeLabel) · \(rule.weekdaysLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if blockedCount == 0 {
                    Text("Aucune app choisie")
                        .font(.caption)
                        .foregroundStyle(Color.amber)
                } else {
                    Text("\(blockedCount) sélection\(blockedCount > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(Color.amber)
        }
        .padding(.vertical, 2)
    }
}
