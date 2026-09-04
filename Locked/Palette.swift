//
//  Palette.swift
//  Créneau
//
//  Slate ground, amber accent: a dial with one sector locked. Deliberately
//  nothing like the green padlock of the project this was forked from — the two
//  apps sat side by side on the home screen and were impossible to tell apart.
//
//  Single dark theme on purpose, the way the original committed to its green.
//  Every colour is painted explicitly; nothing is borrowed from the system.
//

import SwiftUI

extension Color {
    /// Blocking, active, "this window is closed".
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)
    /// Open, idle, "nothing is holding you back".
    static let slate = Color(red: 0.392, green: 0.455, blue: 0.545)
    static let freeState = Color(red: 0.514, green: 0.788, blue: 0.667)

    /// Backgrounds
    static let ground = Color(red: 0.043, green: 0.067, blue: 0.094)
    static let groundTop = Color(red: 0.086, green: 0.125, blue: 0.176)
    static let card = Color(red: 0.098, green: 0.137, blue: 0.184)
    static let cardBorder = Color(red: 0.157, green: 0.204, blue: 0.259)

    /// Dial parts
    static let dialTrack = Color(red: 0.129, green: 0.169, blue: 0.220)
    static let dialTick = Color(red: 0.416, green: 0.478, blue: 0.549)
    static let dialHand = Color(red: 0.902, green: 0.937, blue: 0.965)
}

/// The card every section sits in. One rounded rectangle, one hairline border,
/// no shadows — the dial is the only thing on screen allowed to draw attention.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
