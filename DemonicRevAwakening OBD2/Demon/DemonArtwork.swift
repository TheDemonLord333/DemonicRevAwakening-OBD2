//
//  DemonArtwork.swift
//  DemonicRevAwakening OBD2
//
//  Zeichnet die einzelnen Körperteile des Dämons mit Core Graphics als
//  getrennte Texturen (Kopf, Hörner, Hornleuchten, Ohren, Augen, Lider,
//  Brauen, Maul, Körper, Leuchtpunkte). Jede Ebene wird in `DemonScene`
//  unabhängig animiert. Alle Koordinaten: UIKit (y nach unten) im
//  jeweiligen Zeichenbereich.
//

import SpriteKit
import UIKit

enum DemonArtwork {
    // MARK: - Abmessungen und Ankerpunkte (Entwurfseinheiten)

    static let headSize = CGSize(width: 320, height: 360)
    static let hornSize = CGSize(width: 260, height: 320)
    static let hornBase = CGPoint(x: 232, y: 272)
    static let earSize = CGSize(width: 140, height: 110)
    static let earBase = CGPoint(x: 128, y: 60)
    static let bodySize = CGSize(width: 600, height: 320)
    static let eyeSize = CGSize(width: 96, height: 56)
    static let eyeCenter = CGPoint(x: 50, y: 28)
    static let lidSize = CGSize(width: 96, height: 76)
    static let lidEdgeY: CGFloat = 60
    static let browSize = CGSize(width: 88, height: 42)
    static let browCenter = CGPoint(x: 44, y: 20)
    static let mouthSize = CGSize(width: 160, height: 70)
    static let mouthAnchor = CGPoint(x: 80, y: 20)

    /// Ankerpunkt (SpriteKit, y nach oben) für einen Punkt im Zeichenbereich.
    static func anchor(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / size.width, y: 1 - point.y / size.height)
    }

    // MARK: - Geometrie

    private static let headRight: [CGPoint] = [
        CGPoint(x: 160, y: 8), CGPoint(x: 180, y: 34), CGPoint(x: 210, y: 44), CGPoint(x: 240, y: 66),
        CGPoint(x: 260, y: 100), CGPoint(x: 282, y: 146), CGPoint(x: 262, y: 174), CGPoint(x: 270, y: 206),
        CGPoint(x: 254, y: 238), CGPoint(x: 232, y: 280), CGPoint(x: 204, y: 316), CGPoint(x: 180, y: 338),
        CGPoint(x: 160, y: 348),
    ]

    static var headOutline: [CGPoint] {
        let left = headRight.dropFirst().dropLast().reversed().map { CGPoint(x: 320 - $0.x, y: $0.y) }
        return headRight + left
    }

    private static let hornOuter: [CGPoint] = [
        CGPoint(x: 214, y: 306), CGPoint(x: 132, y: 288), CGPoint(x: 64, y: 240), CGPoint(x: 26, y: 168),
        CGPoint(x: 22, y: 98), CGPoint(x: 38, y: 44), CGPoint(x: 66, y: 6),
    ]
    private static let hornInner: [CGPoint] = [
        CGPoint(x: 66, y: 6), CGPoint(x: 72, y: 52), CGPoint(x: 86, y: 108), CGPoint(x: 120, y: 166),
        CGPoint(x: 170, y: 208), CGPoint(x: 246, y: 236),
    ]

    private static let earOutline: [CGPoint] = [
        CGPoint(x: 132, y: 30), CGPoint(x: 90, y: 40), CGPoint(x: 40, y: 30), CGPoint(x: 6, y: 8),
        CGPoint(x: 30, y: 46), CGPoint(x: 70, y: 80), CGPoint(x: 118, y: 92), CGPoint(x: 136, y: 70),
    ]

    private static let bodyRight: [CGPoint] = [
        CGPoint(x: 342, y: 0), CGPoint(x: 350, y: 56), CGPoint(x: 392, y: 84), CGPoint(x: 452, y: 88),
        CGPoint(x: 500, y: 30), CGPoint(x: 512, y: 96), CGPoint(x: 566, y: 70), CGPoint(x: 548, y: 140),
        CGPoint(x: 590, y: 180), CGPoint(x: 600, y: 320),
    ]

    private static var bodyOutline: [CGPoint] {
        bodyRight + bodyRight.reversed().map { CGPoint(x: 600 - $0.x, y: $0.y) }
    }

    private static let browOutline: [CGPoint] = [
        CGPoint(x: 4, y: 4), CGPoint(x: 46, y: 10), CGPoint(x: 84, y: 28),
        CGPoint(x: 78, y: 38), CGPoint(x: 42, y: 24), CGPoint(x: 6, y: 16),
    ]

    // MARK: - Texturen

    struct Textures {
        let head: SKTexture
        let horn: SKTexture
        let hornGlow: SKTexture
        let ear: SKTexture
        let body: SKTexture
        let eyeball: SKTexture
        let eyeMask: SKTexture
        let lid: SKTexture
        let brow: SKTexture
        let mouth: SKTexture
        let softDot: SKTexture
        let spark: SKTexture
        let flame: SKTexture
    }

    /// Erzeugt alle Texturen einmalig. Auflösung 2× der Entwurfseinheiten.
    static func makeTextures(scale: CGFloat = 2) -> Textures {
        Textures(
            head: render(headSize, scale: scale, drawHead),
            horn: render(hornSize, scale: scale, drawHorn),
            hornGlow: render(hornSize, scale: scale, drawHornGlow),
            ear: render(earSize, scale: scale, drawEar),
            body: render(bodySize, scale: scale, drawBody),
            eyeball: render(eyeSize, scale: scale * 1.5, drawEyeball),
            eyeMask: render(eyeSize, scale: scale * 1.5) { context in
                context.addPath(eyePath())
                context.setFillColor(UIColor.white.cgColor)
                context.fillPath()
            },
            lid: render(lidSize, scale: scale * 1.5, drawLid),
            brow: render(browSize, scale: scale, drawBrow),
            mouth: render(mouthSize, scale: scale, drawMouth),
            softDot: render(CGSize(width: 64, height: 64), scale: 2) { context in
                radialFill(context, center: CGPoint(x: 32, y: 32), radius: 32,
                           colors: [UIColor.white, UIColor.white.withAlphaComponent(0.45), UIColor.white.withAlphaComponent(0)],
                           locations: [0, 0.35, 1])
            },
            spark: render(CGSize(width: 16, height: 16), scale: 2) { context in
                radialFill(context, center: CGPoint(x: 8, y: 8), radius: 8,
                           colors: [UIColor.white, UIColor.white.withAlphaComponent(0)], locations: [0, 1])
            },
            flame: render(CGSize(width: 64, height: 128), scale: 2, drawFlame)
        )
    }

    /// Zeichnet synchron in einen eigenen Bitmap-Kontext mit UIKit-Koordinaten
    /// (Ursprung oben links), damit alles auf dem MainActor bleibt.
    private static func render(_ size: CGSize, scale: CGFloat, _ draw: @MainActor (CGContext) -> Void) -> SKTexture {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return SKTexture()
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        draw(context)
        guard let image = context.makeImage() else { return SKTexture() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }

    // MARK: - Pfad-Hilfen

    /// Geschlossene oder offene Catmull-Rom-Kurve durch die Punkte.
    static func smoothPath(_ points: [CGPoint], closed: Bool = true, tension: CGFloat = 0.5) -> CGMutablePath {
        let path = CGMutablePath()
        guard points.count > 2 else {
            path.addLines(between: points)
            return path
        }
        let count = points.count
        let factor = tension / 3
        path.move(to: points[0])
        let segments = closed ? count : count - 1
        for index in 0..<segments {
            let p0 = closed || index > 0 ? points[(index - 1 + count) % count] : points[index]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = closed || index + 2 < count ? points[(index + 2) % count] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * factor, y: p1.y + (p2.y - p0.y) * factor)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * factor, y: p2.y - (p3.y - p1.y) * factor)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
        return path
    }

    private static func ellipse(center: CGPoint, radius: CGFloat, yScale: CGFloat, rotation: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotation)
            .scaledBy(x: 1, y: yScale)
        return CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
                      transform: &transform)
    }

    private static func gradient(_ colors: [UIColor], _ locations: [CGFloat]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: colors.map(\.cgColor) as CFArray, locations: locations)
    }

    private static func radialFill(_ context: CGContext, center: CGPoint, radius: CGFloat,
                                   colors: [UIColor], locations: [CGFloat]) {
        guard let gradient = gradient(colors, locations) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius, options: [])
    }

    /// Füllt `path` mit einem radialen Verlauf.
    private static func fill(_ context: CGContext, _ path: CGPath, radialAt center: CGPoint, radius: CGFloat,
                             colors: [UIColor], locations: [CGFloat]) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        radialFill(context, center: center, radius: radius, colors: colors, locations: locations)
        context.restoreGState()
    }

    /// Füllt `path` mit einem linearen Verlauf.
    private static func fill(_ context: CGContext, _ path: CGPath, from start: CGPoint, to end: CGPoint,
                             colors: [UIColor], locations: [CGFloat]) {
        guard let gradient = gradient(colors, locations) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    private static func stroke(_ context: CGContext, _ path: CGPath, color: UIColor, width: CGFloat,
                               glow: CGFloat = 0, glowColor: UIColor? = nil) {
        context.saveGState()
        if glow > 0 {
            context.setShadow(offset: .zero, blur: glow, color: (glowColor ?? color).cgColor)
        }
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    /// Deterministischer Zufall, damit die Steinstruktur stabil bleibt.
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func uniform(_ range: ClosedRange<CGFloat>) -> CGFloat {
            let unit = CGFloat(next() >> 11) / CGFloat(1 << 53)
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }
    }

    // MARK: - Kopf

    private static func drawHead(_ context: CGContext) {
        let outline = smoothPath(headOutline, tension: 0.28)
        let violet = Palette.violet

        // Grundform mit plastischem Verlauf.
        fill(context, outline, radialAt: CGPoint(x: 160, y: 150), radius: 210,
             colors: [rgb(0x4A4756), rgb(0x26242E), rgb(0x09080D)], locations: [0, 0.45, 1])

        context.saveGState()
        context.addPath(outline)
        context.clip()

        // Steinstruktur: Facetten.
        var random = SeededRandom(seed: 7)
        for _ in 0..<320 {
            let x = random.uniform(40...280), y = random.uniform(10...350)
            let size = random.uniform(4...16)
            let angle = random.uniform(0...(2 * .pi))
            let facet = CGMutablePath()
            facet.move(to: CGPoint(x: x + cos(angle) * size, y: y + sin(angle) * size))
            for step in 1...2 {
                let a = angle + CGFloat(step) * 2.1 + random.uniform(-0.4...0.4)
                let s = size * random.uniform(0.6...1.1)
                facet.addLine(to: CGPoint(x: x + cos(a) * s, y: y + sin(a) * s))
            }
            facet.closeSubpath()
            let light = random.uniform(0...1) < 0.5
            let alpha = light ? random.uniform(0.02...0.06) : random.uniform(0.08...0.18)
            context.addPath(facet)
            context.setFillColor((light ? UIColor.white : UIColor.black).withAlphaComponent(alpha).cgColor)
            context.fillPath()
        }
        // Risse.
        for _ in 0..<26 {
            var x = random.uniform(50...270), y = random.uniform(20...340)
            let crack = CGMutablePath()
            crack.move(to: CGPoint(x: x, y: y))
            var angle = random.uniform(0...(2 * .pi))
            let segments = Int(random.uniform(3...6.99))
            for _ in 0..<segments {
                angle += random.uniform(-0.8...0.8)
                let length = random.uniform(5...12)
                x += cos(angle) * length
                y += sin(angle) * length
                crack.addLine(to: CGPoint(x: x, y: y))
            }
            stroke(context, crack, color: UIColor.black.withAlphaComponent(0.45), width: 1.1)
        }

        // Stirnkamm.
        let ridge = smoothPath([CGPoint(x: 160, y: 12), CGPoint(x: 176, y: 60), CGPoint(x: 170, y: 120),
                                CGPoint(x: 160, y: 170), CGPoint(x: 150, y: 120), CGPoint(x: 144, y: 60)],
                               tension: 0.3)
        fill(context, ridge, from: CGPoint(x: 160, y: 12), to: CGPoint(x: 160, y: 170),
             colors: [rgb(0x6A6680, 0.9), rgb(0x2A2833, 0)], locations: [0, 1])
        let ridgeLine = CGMutablePath()
        ridgeLine.move(to: CGPoint(x: 160, y: 20))
        ridgeLine.addLine(to: CGPoint(x: 160, y: 168))
        stroke(context, ridgeLine, color: UIColor.black.withAlphaComponent(0.5), width: 1.5)

        for side: CGFloat in [1, -1] {
            // Stirnfurchen.
            let furrow = CGMutablePath()
            furrow.move(to: CGPoint(x: 160 + side * 8, y: 70))
            furrow.addCurve(to: CGPoint(x: 160 + side * 80, y: 104),
                            control1: CGPoint(x: 160 + side * 40, y: 96), control2: CGPoint(x: 160 + side * 40, y: 96))
            stroke(context, furrow, color: UIColor.black.withAlphaComponent(0.55), width: 2.5)

            // Augenhöhlen.
            let socketCenter = CGPoint(x: 160 + side * 46, y: 168)
            fill(context, ellipse(center: socketCenter, radius: 40, yScale: 0.55, rotation: -side * 0.22),
                 radialAt: socketCenter, radius: 44,
                 colors: [rgb(0x050407, 0.95), rgb(0x120F1C, 0.75), rgb(0x1A1626, 0)], locations: [0, 0.6, 1])

            // Wangenschatten und Wangenknochen.
            let hollow = CGPoint(x: 160 + side * 74, y: 228)
            fill(context, ellipse(center: hollow, radius: 36, yScale: 0.45, rotation: side * 0.5),
                 radialAt: hollow, radius: 36,
                 colors: [UIColor.black.withAlphaComponent(0.55), UIColor.black.withAlphaComponent(0)], locations: [0, 1])
            let cheek = CGPoint(x: 160 + side * 82, y: 196)
            fill(context, ellipse(center: cheek, radius: 30, yScale: 0.3, rotation: side * 0.35),
                 radialAt: cheek, radius: 30,
                 colors: [rgb(0x8A86A0, 0.35), rgb(0x8A86A0, 0)], locations: [0, 1])

            // Nasolabialfalten.
            let fold = CGMutablePath()
            fold.move(to: CGPoint(x: 160 + side * 24, y: 230))
            fold.addCurve(to: CGPoint(x: 160 + side * 44, y: 292),
                          control1: CGPoint(x: 160 + side * 40, y: 250), control2: CGPoint(x: 160 + side * 46, y: 272))
            stroke(context, fold, color: UIColor.black.withAlphaComponent(0.5), width: 2.5)
        }

        // Nase.
        let nose = smoothPath([CGPoint(x: 160, y: 182), CGPoint(x: 168, y: 214), CGPoint(x: 178, y: 232),
                               CGPoint(x: 166, y: 240), CGPoint(x: 160, y: 236), CGPoint(x: 154, y: 240),
                               CGPoint(x: 142, y: 232), CGPoint(x: 152, y: 214)], tension: 0.35)
        fill(context, nose, from: CGPoint(x: 160, y: 182), to: CGPoint(x: 160, y: 240),
             colors: [rgb(0x3C3946, 0), rgb(0x4C4858, 0.85), rgb(0x2A2731, 0.9)], locations: [0, 0.6, 1])
        for side: CGFloat in [1, -1] {
            context.addPath(ellipse(center: CGPoint(x: 160 + side * 9, y: 236), radius: 4.5, yScale: 0.55, rotation: 0))
            context.setFillColor(UIColor.black.withAlphaComponent(0.85).cgColor)
            context.fillPath()
        }

        // Geschlossenes Maul mit kleinen Fangzähnen (das offene Maul ist eine eigene Ebene).
        let mouthLine = CGMutablePath()
        mouthLine.move(to: CGPoint(x: 112, y: 268))
        mouthLine.addCurve(to: CGPoint(x: 208, y: 268), control1: CGPoint(x: 135, y: 280), control2: CGPoint(x: 185, y: 280))
        stroke(context, mouthLine, color: UIColor.black.withAlphaComponent(0.9), width: 3.2)
        for fangX: CGFloat in [132, 188] {
            let fang = CGMutablePath()
            fang.addLines(between: [CGPoint(x: fangX - 5, y: 274), CGPoint(x: fangX, y: 288), CGPoint(x: fangX + 5, y: 275.5)])
            fang.closeSubpath()
            fill(context, fang, from: CGPoint(x: fangX, y: 274), to: CGPoint(x: fangX, y: 288),
                 colors: [rgb(0xD8D4C8), rgb(0x8C877C)], locations: [0, 1])
        }

        // Kinnlicht.
        let chin = CGPoint(x: 160, y: 322)
        fill(context, ellipse(center: chin, radius: 18, yScale: 0.4, rotation: 0), radialAt: chin, radius: 18,
             colors: [rgb(0x77738A, 0.4), rgb(0x77738A, 0)], locations: [0, 1])

        // Randlicht: violett, unten grüner Widerschein der Energie.
        stroke(context, outline, color: violet.withAlphaComponent(0.18), width: 26)
        stroke(context, outline, color: violet.withAlphaComponent(0.45), width: 9)
        context.saveGState()
        context.addPath(outline)
        context.setLineWidth(10)
        context.replacePathWithStrokedPath()
        context.clip()
        if let bounce = gradient([rgb(0x1DB954, 0), rgb(0x6BFF8C, 0.35)], [0, 1]) {
            context.drawLinearGradient(bounce, start: CGPoint(x: 0, y: 200), end: CGPoint(x: 0, y: 350), options: [])
        }
        context.restoreGState()
        context.restoreGState()

        stroke(context, outline, color: UIColor.black.withAlphaComponent(0.9), width: 2)
    }

    // MARK: - Hörner

    private static func hornPath() -> CGMutablePath {
        smoothPath(hornOuter + hornInner.dropFirst(), tension: 0.5)
    }

    private static func point(along polyline: [CGPoint], at t: CGFloat) -> CGPoint {
        let position = t.clamped(to: 0...1) * CGFloat(polyline.count - 1)
        let index = min(Int(position), polyline.count - 2)
        let fraction = position - CGFloat(index)
        let a = polyline[index], b = polyline[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    private static func drawHorn(_ context: CGContext) {
        let path = hornPath()
        fill(context, path, from: CGPoint(x: 230, y: 300), to: CGPoint(x: 66, y: 6),
             colors: [rgb(0x121118), rgb(0x2D2A3A), rgb(0x5A5570)], locations: [0, 0.55, 1])

        context.saveGState()
        context.addPath(path)
        context.clip()
        // Querrillen von der Basis zur Spitze.
        let innerFromBase = Array(hornInner.reversed())
        for step in 1..<12 {
            let t = CGFloat(step) / 12
            let outer = point(along: hornOuter, at: t)
            let inner = point(along: innerFromBase, at: t)
            let tipward = point(along: hornOuter, at: min(1, t + 0.06))
            let control = CGPoint(x: (outer.x + inner.x) / 2 + (tipward.x - outer.x) * 0.5,
                                  y: (outer.y + inner.y) / 2 + (tipward.y - outer.y) * 0.5)
            let groove = CGMutablePath()
            groove.move(to: outer)
            groove.addCurve(to: inner, control1: control, control2: control)
            stroke(context, groove, color: UIColor.black.withAlphaComponent(0.6), width: 3.2 - t * 1.8)
            let highlight = CGMutablePath()
            highlight.move(to: CGPoint(x: outer.x + 2, y: outer.y - 3))
            let shifted = CGPoint(x: control.x + 2, y: control.y - 3)
            highlight.addCurve(to: CGPoint(x: inner.x + 2, y: inner.y - 3), control1: shifted, control2: shifted)
            stroke(context, highlight, color: UIColor.white.withAlphaComponent(0.07), width: 1.5)
        }
        let outerEdge = smoothPath(hornOuter, closed: false)
        stroke(context, outerEdge, color: Palette.blurple.withAlphaComponent(0.55), width: 12)
        stroke(context, outerEdge, color: UIColor(red: 0.75, green: 0.7, blue: 1, alpha: 0.5), width: 3)
        context.restoreGState()

        stroke(context, path, color: UIColor.black.withAlphaComponent(0.85), width: 2)
    }

    /// Leuchtkante der Hörner (separat, wird additiv überblendet).
    private static func drawHornGlow(_ context: CGContext) {
        let outerEdge = smoothPath(hornOuter, closed: false)
        stroke(context, outerEdge, color: rgb(0x7A83FF, 0.9), width: 5, glow: 18, glowColor: Palette.violet)
        stroke(context, outerEdge, color: rgb(0xC9CCFF, 0.9), width: 2, glow: 6, glowColor: Palette.blurple)
    }

    // MARK: - Ohren

    private static func drawEar(_ context: CGContext) {
        let path = smoothPath(earOutline, tension: 0.35)
        fill(context, path, from: CGPoint(x: 130, y: 60), to: CGPoint(x: 10, y: 10),
             colors: [rgb(0x15141B), rgb(0x3A3746)], locations: [0, 1])
        let inner = smoothPath([CGPoint(x: 124, y: 50), CGPoint(x: 88, y: 52), CGPoint(x: 40, y: 34),
                                CGPoint(x: 66, y: 64), CGPoint(x: 110, y: 78)], tension: 0.4)
        fill(context, inner, from: CGPoint(x: 120, y: 60), to: CGPoint(x: 40, y: 34),
             colors: [rgb(0x2A0F3D, 0.9), rgb(0x5A2A8A, 0.6)], locations: [0, 1])
        stroke(context, path, color: Palette.violet.withAlphaComponent(0.7), width: 2)
    }

    // MARK: - Körper

    private static func drawBody(_ context: CGContext) {
        let path = smoothPath(bodyOutline, tension: 0.25)
        fill(context, path, from: CGPoint(x: 300, y: 0), to: CGPoint(x: 300, y: 320),
             colors: [rgb(0x2E2B38), rgb(0x17151E), rgb(0x050407)], locations: [0, 0.5, 1])

        context.saveGState()
        context.addPath(path)
        context.clip()
        for side: CGFloat in [1, -1] {
            let plate = smoothPath([CGPoint(x: 300 + side * 40, y: 40), CGPoint(x: 300 + side * 120, y: 100),
                                    CGPoint(x: 300 + side * 210, y: 98), CGPoint(x: 300 + side * 150, y: 160),
                                    CGPoint(x: 300 + side * 30, y: 210)], tension: 0.3)
            fill(context, plate, from: CGPoint(x: 300, y: 40), to: CGPoint(x: 300 + side * 210, y: 160),
                 colors: [rgb(0x3A3746, 0.9), rgb(0x121118, 0.9)], locations: [0, 1])
            stroke(context, plate, color: Palette.violet.withAlphaComponent(0.55), width: 2.2)
        }
        let chest = CGMutablePath()
        chest.addLines(between: [CGPoint(x: 260, y: 40), CGPoint(x: 300, y: 250), CGPoint(x: 340, y: 40)])
        stroke(context, chest, color: UIColor.black.withAlphaComponent(0.6), width: 3)
        stroke(context, path, color: Palette.violet.withAlphaComponent(0.35), width: 10)
        context.restoreGState()

        // Unten weich in den Nebel ausblenden.
        context.saveGState()
        context.setBlendMode(.destinationOut)
        if let fade = gradient([UIColor.black.withAlphaComponent(0), UIColor.black], [0, 1]) {
            context.clip(to: CGRect(x: 0, y: 150, width: 600, height: 170))
            context.drawLinearGradient(fade, start: CGPoint(x: 0, y: 170), end: CGPoint(x: 0, y: 318),
                                       options: [.drawsAfterEndLocation])
        }
        context.restoreGState()
    }

    // MARK: - Augen

    static func eyePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 6, y: 22))
        path.addCurve(to: CGPoint(x: 90, y: 34), control1: CGPoint(x: 26, y: 4), control2: CGPoint(x: 62, y: 6))
        path.addCurve(to: CGPoint(x: 6, y: 22), control1: CGPoint(x: 62, y: 46), control2: CGPoint(x: 26, y: 44))
        path.closeSubpath()
        return path
    }

    private static func drawEyeball(_ context: CGContext) {
        fill(context, eyePath(), radialAt: CGPoint(x: 50, y: 28), radius: 46,
             colors: [rgb(0xF4FFF6), rgb(0x9DFFB4), rgb(0x1DB954), rgb(0x0A4A22)], locations: [0, 0.25, 0.6, 1])
        // Geschlitzte Pupille.
        context.addEllipse(in: CGRect(x: 50 - 3.1, y: 28 - 11, width: 6.2, height: 22))
        context.setFillColor(UIColor(red: 0.01, green: 0.08, blue: 0.03, alpha: 0.95).cgColor)
        context.fillPath()
    }

    /// Oberlid: Fläche oberhalb einer gebogenen Kante bei `lidEdgeY`.
    private static func drawLid(_ context: CGContext) {
        let edge = lidEdgeY
        let lid = CGMutablePath()
        lid.move(to: .zero)
        lid.addLine(to: CGPoint(x: 96, y: 0))
        lid.addLine(to: CGPoint(x: 96, y: edge + 6))
        lid.addCurve(to: CGPoint(x: 0, y: edge - 6), control1: CGPoint(x: 70, y: edge + 10), control2: CGPoint(x: 30, y: edge + 2))
        lid.closeSubpath()
        fill(context, lid, from: CGPoint(x: 0, y: edge - 50), to: CGPoint(x: 0, y: edge),
             colors: [rgb(0x2B2934), rgb(0x1A1820)], locations: [0, 1])
        let lash = CGMutablePath()
        lash.move(to: CGPoint(x: 96, y: edge + 6))
        lash.addCurve(to: CGPoint(x: 0, y: edge - 6), control1: CGPoint(x: 70, y: edge + 10), control2: CGPoint(x: 30, y: edge + 2))
        stroke(context, lash, color: UIColor(red: 0.02, green: 0.01, blue: 0.04, alpha: 1), width: 2.4)
    }

    private static func drawBrow(_ context: CGContext) {
        let path = smoothPath(browOutline, tension: 0.2)
        fill(context, path, from: .zero, to: CGPoint(x: 0, y: 42),
             colors: [rgb(0x3B3848), rgb(0x0C0B10)], locations: [0, 1])
        let edge = CGMutablePath()
        edge.move(to: CGPoint(x: 4, y: 4))
        edge.addCurve(to: CGPoint(x: 84, y: 28), control1: CGPoint(x: 32, y: 6), control2: CGPoint(x: 60, y: 14))
        stroke(context, edge, color: Palette.violet.withAlphaComponent(0.6), width: 1.8)
    }

    // MARK: - Offenes Maul

    private static func mouthPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 14, y: 14))
        path.addCurve(to: CGPoint(x: 146, y: 14), control1: CGPoint(x: 50, y: 28), control2: CGPoint(x: 110, y: 28))
        path.addCurve(to: CGPoint(x: 14, y: 14), control1: CGPoint(x: 116, y: 62), control2: CGPoint(x: 44, y: 62))
        path.closeSubpath()
        return path
    }

    private static func drawMouth(_ context: CGContext) {
        let path = mouthPath()
        fill(context, path, radialAt: CGPoint(x: 80, y: 36), radius: 60,
             colors: [rgb(0x2FFF6A, 0.95), rgb(0x0D4D22), rgb(0x020403)], locations: [0, 0.35, 1])
        context.saveGState()
        context.addPath(path)
        context.clip()
        let upper: [(CGFloat, CGFloat, CGFloat)] = [(30, 26, 9), (52, 12, 6), (68, 10, 5), (92, 10, 5), (108, 12, 6), (130, 26, 9)]
        for (x, length, width) in upper {
            let tooth = CGMutablePath()
            tooth.addLines(between: [CGPoint(x: x - width, y: 16), CGPoint(x: x, y: 16 + length), CGPoint(x: x + width, y: 16)])
            tooth.closeSubpath()
            fill(context, tooth, from: CGPoint(x: x, y: 16), to: CGPoint(x: x, y: 16 + length),
                 colors: [rgb(0xE8E4D8), rgb(0x9A9488)], locations: [0, 1])
        }
        let lower: [(CGFloat, CGFloat, CGFloat)] = [(46, 16, 6), (114, 16, 6), (80, 8, 5)]
        for (x, length, width) in lower {
            let tooth = CGMutablePath()
            tooth.addLines(between: [CGPoint(x: x - width, y: 60), CGPoint(x: x, y: 60 - length), CGPoint(x: x + width, y: 60)])
            tooth.closeSubpath()
            fill(context, tooth, from: CGPoint(x: x, y: 60), to: CGPoint(x: x, y: 60 - length),
                 colors: [rgb(0x9A9488), rgb(0xE8E4D8)], locations: [0, 1])
        }
        context.restoreGState()
        stroke(context, path, color: .black, width: 2.5)
    }

    // MARK: - Partikel

    /// Weiche, senkrecht gestreckte Leuchtzunge ohne harte Kanten.
    private static func drawFlame(_ context: CGContext) {
        context.saveGState()
        context.translateBy(x: 32, y: 64)
        context.scaleBy(x: 1, y: 2)
        radialFill(context, center: .zero, radius: 30,
                   colors: [UIColor.white.withAlphaComponent(0.95), UIColor.white.withAlphaComponent(0.4),
                            UIColor.white.withAlphaComponent(0)],
                   locations: [0, 0.4, 1])
        context.restoreGState()
    }
}
