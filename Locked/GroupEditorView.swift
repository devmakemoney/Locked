//
//  GroupEditorView.swift
//  Créneau
//
//  One group: the apps, then as many time windows as you need.
//
//  The apps are picked once at the top. Adding a second window does not ask you
//  to pick them again — that was the whole point of the group model.
//

import SwiftUI
import FamilyControls

struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ScheduleStore

    let existing: BlockGroup?
    /// Day pre-checked when the group is created by tapping a grid column.
    let initialDay: Int?

    @State private var name: String = ""
    @State private var windows: [TimeWindow] = []
    @State private var isEnabled: Bool = true
    @State private var selection = FamilyActivitySelection()
    @State private var isPickingApps = false
    @State private var editingWindow: TimeWindow?
    @State private var webDomains: [String] = []
    @State private var newDomain: String = ""
    @State private var domainError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom du groupe") {
                    TextField("Loisir, Travail, Nuit…", text: $name)
                }

                appsSection
                webSection
                windowsSection

                Section {
                    Toggle("Groupe actif", isOn: $isEnabled)
                        .tint(Color.amber)
                }

                if let existing {
                    Section {
                        Button("Supprimer ce groupe", role: .destructive) {
                            store.delete(existing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Nouveau groupe" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { commit() }
                        .disabled(!isValid)
                }
            }
            .familyActivityPicker(isPresented: $isPickingApps, selection: $selection)
            .sheet(item: $editingWindow) { window in
                WindowEditorView(window: window) { updated in
                    if let index = windows.firstIndex(where: { $0.id == updated.id }) {
                        windows[index] = updated
                    }
                } onDelete: {
                    windows.removeAll { $0.id == window.id }
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Apps

    private var appsSection: some View {
        Section {
            Button {
                isPickingApps = true
            } label: {
                HStack {
                    Label("Choisir les apps", systemImage: "app.badge")
                    Spacer()
                    Text(selectionLabel)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Apps bloquées")
        } footer: {
            Text(blockedCount == 0
                 ? "Sans app ni site choisi, le groupe ne bloque rien."
                 : "Ces apps valent pour toutes les plages ci-dessous.")
            .foregroundStyle(blockedCount == 0 ? Color.amber : .secondary)
        }
    }

    // MARK: - Websites

    private var webSection: some View {
        Section {
            ForEach(webDomains, id: \.self) { domain in
                Text(domain)
            }
            .onDelete { webDomains.remove(atOffsets: $0) }

            HStack {
                TextField("reddit.com", text: $newDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(addDomain)
                Button("Ajouter", action: addDomain)
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Sites web bloqués")
        } footer: {
            if let domainError {
                Text(domainError).foregroundStyle(Color.amber)
            } else {
                Text("Le sous-domaine est inclus : bloquer reddit.com bloque aussi www.reddit.com. Fonctionne dans Safari et les navigateurs qui respectent les restrictions du système.")
            }
        }
    }

    private func addDomain() {
        guard let clean = BlockGroup.normalizeDomain(newDomain) else {
            domainError = "Adresse invalide. Écris par exemple reddit.com."
            return
        }
        guard !webDomains.contains(clean) else {
            domainError = "\(clean) est déjà dans la liste."
            newDomain = ""
            return
        }
        webDomains.append(clean)
        newDomain = ""
        domainError = nil
    }

    // MARK: - Windows

    private var windowsSection: some View {
        Section {
            ForEach(windows) { window in
                Button {
                    editingWindow = window
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.rangeLabel)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(window.weekdaysLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(window.durationLabel)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { windows.remove(atOffsets: $0) }

            Button {
                addWindow()
            } label: {
                Label("Ajouter une plage", systemImage: "plus.circle")
            }
        } header: {
            Text("Plages horaires")
        } footer: {
            Text(windows.isEmpty
                 ? "Ajoute autant de plages que nécessaire : 00h–08h, 10h–14h, 17h–00h…"
                 : "Une plage qui finit avant son début se termine le lendemain matin.")
        }
    }

    // MARK: - Helpers

    private var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count
    }

    private var selectionLabel: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        if apps == 0 && categories == 0 { return "Aucune" }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps > 1 ? "s" : "")") }
        if categories > 0 { parts.append("\(categories) catégorie\(categories > 1 ? "s" : "")") }
        return parts.joined(separator: ", ")
    }

    private var isValid: Bool {
        !windows.isEmpty && windows.allSatisfy { !$0.weekdays.isEmpty && $0.durationMinutes > 0 }
    }

    private var blockedCount: Int {
        selectionCount + webDomains.count
    }

    private func load() {
        guard let existing else {
            // A brand new group starts with one window, so there is something
            // to edit right away.
            if windows.isEmpty {
                let days: Set<Int> = initialDay.map { [$0] } ?? [2, 3, 4, 5, 6]
                windows = [TimeWindow(weekdays: days, startMinutes: 9 * 60, endMinutes: 17 * 60)]
            }
            return
        }
        name = existing.name
        windows = existing.windows
        webDomains = existing.webDomains
        isEnabled = existing.isEnabled
        selection = store.selection(for: existing.id)
    }

    /// New windows inherit the previous one's days — you are usually adding a
    /// second slot to the same routine, not starting over.
    private func addWindow() {
        let days = windows.last?.weekdays ?? [2, 3, 4, 5, 6]
        let start = windows.last.map { min(($0.endMinutes + 60) % 1440, 1380) } ?? 9 * 60
        let new = TimeWindow(weekdays: days, startMinutes: start, endMinutes: min(start + 120, 1439))
        windows.append(new)
        editingWindow = new
    }

    private func commit() {
        let group = BlockGroup(
            id: existing?.id ?? UUID(),
            name: name.isEmpty ? "Sans nom" : name,
            windows: windows.sorted { $0.startMinutes < $1.startMinutes },
            webDomains: webDomains,
            isEnabled: isEnabled
        )
        store.save(group, selection: selection)
        dismiss()
    }
}

// MARK: - Window editor

struct WindowEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var weekdays: Set<Int>
    @State private var startMinutes: Int
    @State private var endMinutes: Int

    private let windowID: UUID
    private let onSave: (TimeWindow) -> Void
    private let onDelete: () -> Void

    init(window: TimeWindow, onSave: @escaping (TimeWindow) -> Void, onDelete: @escaping () -> Void) {
        self.windowID = window.id
        _weekdays = State(initialValue: window.weekdays)
        _startMinutes = State(initialValue: window.startMinutes)
        _endMinutes = State(initialValue: window.endMinutes)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Jours") {
                    WeekdayPicker(selection: $weekdays)
                    HStack {
                        Button("Lun – Ven") { weekdays = [2, 3, 4, 5, 6] }
                        Spacer()
                        Button("Week-end") { weekdays = [1, 7] }
                        Spacer()
                        Button("Tous") { weekdays = [1, 2, 3, 4, 5, 6, 7] }
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                }

                Section {
                    TimeRow(label: "Début", minutes: $startMinutes)
                    TimeRow(label: "Fin", minutes: $endMinutes)
                } footer: {
                    Text(endMinutes <= startMinutes
                         ? "Se termine le lendemain matin. Durée : \(durationLabel)."
                         : "Durée : \(durationLabel).")
                }

                Section {
                    Button("Supprimer cette plage", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Plage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onSave(TimeWindow(id: windowID, weekdays: weekdays,
                                          startMinutes: startMinutes, endMinutes: endMinutes))
                        dismiss()
                    }
                    .disabled(weekdays.isEmpty || startMinutes == endMinutes)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var durationLabel: String {
        let total = endMinutes <= startMinutes
            ? (1440 - startMinutes) + endMinutes
            : endMinutes - startMinutes
        return total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min"
    }
}

// MARK: - Shared pieces

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TimeWindow.orderedWeekdays, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(String(TimeWindow.shortName(day).prefix(1)))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.amber : Color.secondary.opacity(0.15))
                        .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TimeWindow.shortName(day))
            }
        }
        .padding(.vertical, 4)
    }
}

struct TimeRow: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(
            label,
            selection: Binding(
                get: { Self.date(from: minutes) },
                set: { minutes = Self.minutes(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private static func date(from minutes: Int) -> Date {
        let base = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: minutes, to: base) ?? base
    }

    private static func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
