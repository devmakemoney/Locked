//
//  Palette.swift
//  Créneau
//
//  Slate and amber: a dial with one sector locked. Deliberately nothing like
//  the green padlock of the project this was forked from — the two apps sat
//  side by side on the home screen and were impossible to tell apart.
//

import SwiftUI

extension Color {
    /// Blocking, active, "this window is closed".
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)
    /// Open, idle, "nothing is holding you back".
    static let slate = Color(red: 0.392, green: 0.455, blue: 0.545)
}
