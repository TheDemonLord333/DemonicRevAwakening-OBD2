//
//  Theme.swift
//  DemonicRevAwakening OBD2
//
//  Farbwelt passend zum App-Icon: fast schwarz, Spotify-Grün,
//  Discord-Blau-Violett und kräftige violette Akzente.
//

import SwiftUI
import UIKit

enum Palette {
    /// Fast schwarzer Hintergrund.
    static let night = UIColor(red: 0.020, green: 0.016, blue: 0.035, alpha: 1)
    static let nightRaised = UIColor(red: 0.063, green: 0.051, blue: 0.098, alpha: 1)
    /// Spotify-Grün #1DB954.
    static let green = UIColor(red: 29 / 255, green: 185 / 255, blue: 84 / 255, alpha: 1)
    /// Hellere grüne Leuchteffekte.
    static let neonGreen = UIColor(red: 0.42, green: 1.0, blue: 0.55, alpha: 1)
    static let paleGreen = UIColor(red: 0.85, green: 1.0, blue: 0.88, alpha: 1)
    /// Discord-Blau-Violett #5865F2.
    static let blurple = UIColor(red: 88 / 255, green: 101 / 255, blue: 242 / 255, alpha: 1)
    /// Kräftiges Violett für Akzente.
    static let violet = UIColor(red: 0.60, green: 0.30, blue: 0.98, alpha: 1)
    static let deepViolet = UIColor(red: 0.27, green: 0.10, blue: 0.52, alpha: 1)
    /// Dunkler, steinerner Hautton der Figur.
    static let skinLight = UIColor(red: 0.27, green: 0.26, blue: 0.31, alpha: 1)
    static let skin = UIColor(red: 0.15, green: 0.145, blue: 0.18, alpha: 1)
    static let skinDark = UIColor(red: 0.055, green: 0.05, blue: 0.075, alpha: 1)
    static let bone = UIColor(red: 0.84, green: 0.82, blue: 0.76, alpha: 1)
}

enum Theme {
    static let background = Color(Palette.night)
    static let surface = Color(Palette.nightRaised)
    static let green = Color(Palette.green)
    static let neonGreen = Color(Palette.neonGreen)
    static let blurple = Color(Palette.blurple)
    static let violet = Color(Palette.violet)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.5)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.45)

    /// Verlauf Grün → Blau-Violett → Violett, wie der Drehzahlbogen im Icon.
    static let energyGradient = Gradient(colors: [green, neonGreen, blurple, violet])

    static func color(for mood: DemonMood) -> Color {
        switch mood {
        case .disconnected, .waitingForData: textTertiary
        case .engineOff, .idle: blurple
        case .awakening: green
        case .awake: neonGreen
        case .unleashed: violet
        }
    }
}

/// Dezent leuchtende, abgerundete Fläche für Bedienelemente.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Theme.blurple.opacity(0.45), Theme.green.opacity(0.25)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

/// Großer, gut lesbarer Hauptbutton (mindestens 44 pt hoch).
struct DemonButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(kind == .primary ? Color.black : Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(color: kind == .primary ? Theme.green.opacity(0.45) : .clear, radius: 12)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary:
            AnyShapeStyle(LinearGradient(colors: [Theme.neonGreen, Theme.green],
                                         startPoint: .top, endPoint: .bottom))
        case .secondary:
            AnyShapeStyle(Theme.surface.opacity(0.9))
        case .destructive:
            AnyShapeStyle(Theme.danger.opacity(0.18))
        }
    }

    private var border: Color {
        switch kind {
        case .primary: Theme.neonGreen.opacity(0.6)
        case .secondary: Theme.blurple.opacity(0.55)
        case .destructive: Theme.danger.opacity(0.6)
        }
    }
}
