//
//  ScheduleEditorView.swift
//  Locked
//
//  One rule: which apps, which days, which hours.
//

import SwiftUI
import FamilyControls

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ScheduleStore

    let existing: ScheduleRule?

    @State private var name: String = ""
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var startMinutes: Int = 9 * 60
    @State private var endMinutes: Int = 17 * 60
    @State private var isEnabled: Bool = true
    @State private var selection = FamilyActivitySelection()
    @State private var isPickingApps = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Travail, Loisir, Nuit…", text: $name)
                }

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
                    if selectionCount == 0 {
                        Text("Sans app choisie, la règle ne bloque rien.")
                            .foregroundStyle(Color.amber)
                    }
                }

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
                } header: {
                    Text("Horaires")
                } footer: {
                    if endMinutes <= startMinutes {
                        Text("Se termine le lendemain matin. Durée : \(durationLabel).")
                    } else {
                        Text("Durée : \(durationLabel).")
                    }
                }

                Section {
                    Toggle("Règle active", isOn: $isEnabled)
                }

                if let existing {
                    Section {
                        Button("Supprimer cette règle", role: .destructive) {
                            store.delete(existing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Nouvelle règle" : "Modifier")
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
            .onAppear(perform: load)
        }
    }

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
        !weekdays.isEmpty && startMinutes != endMinutes
    }

    private var durationLabel: String {
        let total = endMinutes <= startMinutes
            ? (1440 - startMinutes) + endMinutes
            : endMinutes - startMinutes
        return total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min"
    }

    private func load() {
        guard let existing else { return }
        name = existing.name
        weekdays = existing.weekdays
        startMinutes = existing.startMinutes
        endMinutes = existing.endMinutes
        isEnabled = existing.isEnabled
        selection = store.selection(for: existing.id)
    }

    private func commit() {
        let rule = ScheduleRule(
            id: existing?.id ?? UUID(),
            name: name.isEmpty ? "Sans nom" : name,
            weekdays: weekdays,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            isEnabled: isEnabled
        )
        store.save(rule, selection: selection)
        dismiss()
    }
}

// MARK: - Pieces

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScheduleRule.orderedWeekdays, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(String(ScheduleRule.shortName(day).prefix(1)))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.amber : Color.secondary.opacity(0.15))
                        .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ScheduleRule.shortName(day))
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
