//
//  Profile.swift
//  Locked — shared between the app and the LockedMonitor extension
//
//  Moved out of ProfileManager so the extension can decode profiles too.
//

import Foundation
import FamilyControls
import ManagedSettings

struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var appTokens: Set<ApplicationToken>
    var categoryTokens: Set<ActivityCategoryToken>
    var icon: String
    var isAllowListMode: Bool

    var isDefault: Bool {
        name == "Locked"
    }

    init(
        id: UUID = UUID(),
        name: String,
        appTokens: Set<ApplicationToken>,
        categoryTokens: Set<ActivityCategoryToken>,
        icon: String = "bell.slash",
        isAllowListMode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.appTokens = appTokens
        self.categoryTokens = categoryTokens
        self.icon = icon
        self.isAllowListMode = isAllowListMode
    }
}
