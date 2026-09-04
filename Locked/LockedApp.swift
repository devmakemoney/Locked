//
//  LockedApp.swift
//  Locked
//
//  Created by Brandon Scott on 2025-06-11.
//

import SwiftUI

@main
struct LockedApp: App {
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @StateObject private var profileManager = ProfileManager()
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainAppView(profileManager: profileManager)
            } else {
                OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
                    .environmentObject(profileManager)
            }
        }
    }
}

struct MainAppView: View {
    @StateObject private var appLocker = AppLocker()
    @ObservedObject var profileManager: ProfileManager
    
    var body: some View {
        TabView {
            LockedView()
                .tabItem { Label("Verrou", systemImage: "lock.fill") }

            SchedulesView()
                .tabItem { Label("Plannings", systemImage: "calendar") }
        }
        .environmentObject(appLocker)
        .environmentObject(profileManager)
        .onAppear {
            SharedStore.migrateIfNeeded()
            // Re-arm the rolling DeviceActivity window on every launch.
            ScheduleManager.refresh()
        }
    }
}
