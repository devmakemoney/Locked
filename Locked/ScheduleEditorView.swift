//
//  ScheduleEditorView.swift
//  Locked
//
//  One rule: which profile, which days, which hours.
//

import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileManager: ProfileManager
    @ObservedObject var store: ScheduleStore

    let existing: ScheduleRule?

    @State private var name: String = ""
    @State private var profileID: UUID?
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var startMinutes: Int = 9 * 60
    @State private var endMinutes: Int = 17 * 60
    @State private var isEnabled: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Travail, Loisir, Nuit…", text: $name)
                }

                Section("Profil bloqué") {
                    Picker("Profil", selection: $profileID) {
                        ForEach(profileManager.profiles) { profile in
                            Label(profile.name, systemImage: profile.icon)
                                .tag(Optional(profile.id))
                        }
                    }
                    if let profile = profileManager.profiles.first(where: { $0.id == profileID }) {
                        Text(profile.isAllowListMode
                             ? "Liste blanche : tout est bloqué sauf \(profile.appTokens.count) app(s)."
                             : "\(profile.appTokens.count) app(s) et \(profile.categoryTokens.count) catégorie(s) bloquées.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

                Section("Horaires") {
                    TimeRow(label: "Début", minutes: $startMinutes)
                    TimeRow(label: "Fin", minutes: $endMinutes)
                    if endMinutes <= startMinutes {
                        Label("Se termine le lendemain matin.", systemImage: "moon.stars")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Durée : \(durationLabel)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .onAppear(perform: load)
        }
    }

    private var isValid: Bool {
        profileID != nil && !weekdays.isEmpty && startMinutes != endMinutes
    }

    private var durationLabel: String {
        let total = endMinutes <= startMinutes
            ? (1440 - startMinutes) + endMinutes
            : endMinutes - startMinutes
        return total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min"
    }

    private func load() {
        guard let existing else {
            profileID = profileID ?? profileManager.profiles.first?.id
            return
        }
        name = existing.name
        profileID = existing.profileID
        weekdays = existing.weekdays
        startMinutes = existing.startMinutes
        endMinutes = existing.endMinutes
        isEnabled = existing.isEnabled
    }

    private func commit() {
        guard let profileID else { return }
        let rule = ScheduleRule(
            id: existing?.id ?? UUID(),
            name: name.isEmpty ? "Sans nom" : name,
            profileID: profileID,
            weekdays: weekdays,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            isEnabled: isEnabled
        )
        store.save(rule)
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
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
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
