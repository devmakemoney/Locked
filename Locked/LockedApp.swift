//
//  LockedApp.swift
//  Locked
//

import SwiftUI

@main
struct LockedApp: App {
    var body: some Scene {
        WindowGroup {
            SchedulesView()
                .onAppear {
                    // Re-arm the rolling DeviceActivity window on every launch.
                    ScheduleManager.refresh()
                }
        }
    }
}
