//
//  TachometerView.swift
//  DemonicRevAwakening OBD2
//
//  Dezenter, halbkreisförmiger Drehzahlmesser im Stil des App-Icons.
//

import SwiftUI
import UIKit

struct TachometerView: View {
    /// Geglättete Drehzahl; `nil`, wenn keine gültigen Daten vorliegen.
    var rpm: Double?
    var thresholds: RPMThresholds
    var energy: Double
    var isDimmed: Bool

    var body: some View {
        Canvas { context, size in
            let lineWidth = max(4, size.width * 0.018)
            let radius = min(size.width / 2, size.height) - lineWidth * 2
            let center = CGPoint(x: size.width / 2, y: size.height - lineWidth)
            let maxRPM = max(thresholds.scaleMax, 1)

            func point(_ fraction: Double, _ r: CGFloat) -> CGPoint {
                let angle = Double.pi + Double.pi * fraction.clamped(to: 0...1)
                return CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
            }

            func arc(from start: Double, to end: Double, radius r: CGFloat) -> Path {
                Path { path in
                    let steps = max(2, Int((end - start) * 120))
                    path.move(to: point(start, r))
                    for step in 1...steps {
                        path.addLine(to: point(start + (end - start) * Double(step) / Double(steps), r))
                    }
                }
            }

            // Grundbahn
            context.stroke(arc(from: 0, to: 1, radius: radius),
                           with: .color(.white.opacity(0.08)),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Skalenstriche: groß je 1.000, klein je 500 RPM.
            var value = 0.0
            while value <= maxRPM + 1 {
                let fraction = value / maxRPM
                let isMajor = Int(value) % 1_000 == 0
                let inner = radius - lineWidth * (isMajor ? 2.6 : 1.8)
                let outer = radius - lineWidth * 1.1
                var tick = Path()
                tick.move(to: point(fraction, inner))
                tick.addLine(to: point(fraction, outer))
                let reached = (rpm ?? -1) >= value
                context.stroke(tick,
                               with: .color(reached && !isDimmed ? Self.color(at: fraction) : .white.opacity(isMajor ? 0.35 : 0.18)),
                               style: StrokeStyle(lineWidth: isMajor ? 2.5 : 1.5, lineCap: .round))
                if isMajor {
                    let label = Text("\(Int(value / 1_000))")
                        .font(.system(size: max(10, size.width * 0.032), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                    context.draw(label, at: point(fraction, radius - lineWidth * 4.4))
                }
                value += 500
            }

            // Markierungen der Zustandsschwellen.
            for threshold in [thresholds.awakeningStart, thresholds.awakeStart, thresholds.unleashedStart] {
                let marker = Path(ellipseIn: CGRect(origin: point(threshold / maxRPM, radius + lineWidth * 1.4),
                                                    size: .zero).insetBy(dx: -2, dy: -2))
                context.fill(marker, with: .color(.white.opacity(0.35)))
            }

            // Fortschrittsbogen mit Verlauf und Leuchten.
            if let rpm, rpm > 0 {
                let fraction = (rpm / maxRPM).clamped(to: 0...1)
                var glowContext = context
                glowContext.addFilter(.blur(radius: lineWidth * (0.8 + 1.6 * energy)))
                let segments = max(1, Int(fraction * 90))
                for index in 0..<segments {
                    let start = fraction * Double(index) / Double(segments)
                    let end = fraction * Double(index + 1) / Double(segments)
                    let segment = arc(from: start, to: min(fraction, end + 0.004), radius: radius)
                    let color = Self.color(at: end).opacity(isDimmed ? 0.3 : 1)
                    glowContext.stroke(segment, with: .color(color.opacity(0.55)),
                                       style: StrokeStyle(lineWidth: lineWidth * 1.6, lineCap: .butt))
                    context.stroke(segment, with: .color(color),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
                // Leuchtender Zeigerpunkt.
                let tip = point(fraction, radius)
                let dot = Path(ellipseIn: CGRect(x: tip.x - lineWidth, y: tip.y - lineWidth,
                                                 width: lineWidth * 2, height: lineWidth * 2))
                glowContext.fill(dot, with: .color(Self.color(at: fraction)))
                context.fill(dot, with: .color(.white.opacity(isDimmed ? 0.4 : 0.95)))
            }
        }
        .accessibilityHidden(true)
    }

    /// Farbverlauf Grün → Neongrün → Blau-Violett → Violett.
    static func color(at fraction: Double) -> Color {
        let stops: [(Double, UIColor)] = [(0, Palette.green), (0.35, Palette.neonGreen),
                                          (0.7, Palette.blurple), (1, Palette.violet)]
        let f = fraction.clamped(to: 0...1)
        for index in 1..<stops.count where f <= stops[index].0 {
            let (x0, c0) = stops[index - 1]
            let (x1, c1) = stops[index]
            return Color(Self.mix(c0, c1, (f - x0) / (x1 - x0)))
        }
        return Color(Palette.violet)
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ t: Double) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(t)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
