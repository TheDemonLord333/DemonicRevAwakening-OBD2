//
//  DemonScene.swift
//  DemonicRevAwakening OBD2
//
//  Rendert den Dämon als mehrteilige SpriteKit-Figur. Die Szene läuft mit
//  eigener Bildrate und liest bei jedem Frame die aktuelle Eingabe – die
//  Animation ist damit unabhängig vom OBD-Abfragetakt flüssig.
//

import SpriteKit
import UIKit

/// Darstellungsoptionen aus den Einstellungen und der Bedienungshilfe
/// „Bewegung reduzieren“.
struct DemonRenderSettings: Equatable {
    var animationIntensity: Double = AppSettings.standard.animationIntensity
    var eyeGlowStrength: Double = AppSettings.standard.eyeGlowStrength
    var particleStrength: Double = AppSettings.standard.particleStrength
    var reducedEffects = false
    var reduceMotion = false
}

final class DemonScene: SKScene {
    /// Liefert bei jedem Frame die aktuelle Eingabe (Live, Demo oder keine).
    var inputProvider: () -> DemonInput = { .noConnection }
    /// Meldet Zustand und Energie gedrosselt (ca. 10 Hz) und bei Zustandswechseln.
    var onFrame: ((DemonFrame) -> Void)?

    var renderSettings = DemonRenderSettings() {
        didSet {
            guard renderSettings != oldValue else { return }
            applyAmbientSettings()
        }
    }

    var thresholds: RPMThresholds {
        get { brain.thresholds }
        set { brain.thresholds = newValue.normalized() }
    }

    private(set) var currentFrame = DemonFrame.resting

    private var brain = DemonBrain()
    private var isBuilt = false

    // Ebenen
    private let root = SKNode()
    private let fogLayer = SKNode()
    private var fogSprites: [SKSpriteNode] = []
    private let auraNode = SKNode()
    private var auraOuter = SKSpriteNode()
    private var auraInner = SKSpriteNode()
    private var flamesGreen = SKEmitterNode()
    private var flamesViolet = SKEmitterNode()
    private var embers = SKEmitterNode()
    private var body = SKSpriteNode()
    private let headLift = SKNode()
    private let headSway = SKNode()
    private let headMicro = SKNode()
    private var head = SKSpriteNode()
    private var horns: [SKSpriteNode] = []
    private var hornGlows: [SKSpriteNode] = []
    private var ears: [SKSpriteNode] = []
    private var eyeGlows: [SKSpriteNode] = []
    private var lids: [SKSpriteNode] = []
    private var brows: [SKSpriteNode] = []
    private var mouth = SKSpriteNode()
    private var mouthGlow = SKSpriteNode()
    private var dimmableSprites: [SKSpriteNode] = []

    // Zeitliche Größen
    private var lastUpdateTime: TimeInterval?
    private var clock: TimeInterval = 0
    private var breathPhase: Double = 0
    private var breathRate: Double = 0.2
    private var dimming: Double = 0
    private var blinkRemaining: TimeInterval = 0
    private var nextBlink: TimeInterval = 4
    private var nextMicroMovement: TimeInterval = 5
    private var nextZ: TimeInterval = 2
    private var lastReportTime: TimeInterval = -1
    private var lastReportedMood: DemonMood?
    private var textures: DemonArtwork.Textures?

    private static let lidClosedY: CGFloat = -16
    private static let lidTravel: CGFloat = 42
    private static let headScale: CGFloat = 1.18

    override init(size: CGSize) {
        super.init(size: size)
        configureScene()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configureScene()
    }

    private func configureScene() {
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        if !isBuilt { build() }
        layoutFigure()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if isBuilt { layoutFigure() }
    }

    // MARK: - Aufbau

    private func build() {
        isBuilt = true
        let textures = DemonArtwork.makeTextures()
        self.textures = textures

        fogLayer.zPosition = -100
        addChild(fogLayer)
        let fogColors = [Palette.violet, Palette.blurple, Palette.deepViolet, Palette.green, Palette.violet]
        for color in fogColors {
            let fog = SKSpriteNode(texture: textures.softDot)
            fog.color = color
            fog.colorBlendFactor = 1
            fog.blendMode = .add
            fog.alpha = 0.09
            fogLayer.addChild(fog)
            fogSprites.append(fog)
        }

        addChild(root)

        auraNode.position = CGPoint(x: 0, y: 30)
        auraNode.zPosition = -20
        root.addChild(auraNode)
        auraOuter = glowSprite(textures.softDot, color: Palette.violet, size: 1_150)
        auraNode.addChild(auraOuter)
        auraInner = glowSprite(textures.softDot, color: Palette.green, size: 760)
        auraInner.zPosition = 1
        auraNode.addChild(auraInner)

        flamesViolet = makeFlames(texture: textures.wisp, colors: [Palette.blurple, Palette.violet, Palette.deepViolet])
        flamesViolet.position = CGPoint(x: 0, y: -230)
        flamesViolet.zPosition = -8
        root.addChild(flamesViolet)
        flamesGreen = makeFlames(texture: textures.wisp, colors: [Palette.paleGreen, Palette.neonGreen, Palette.green])
        flamesGreen.position = CGPoint(x: 0, y: -250)
        flamesGreen.zPosition = -7
        root.addChild(flamesGreen)

        body = SKSpriteNode(texture: textures.body, size: DemonArtwork.bodySize)
        body.anchorPoint = CGPoint(x: 0.5, y: 1)
        body.position = CGPoint(x: 0, y: -150)
        body.setScale(0.9)
        body.zPosition = -4
        root.addChild(body)

        headLift.zPosition = 0
        root.addChild(headLift)
        headLift.addChild(headSway)
        headSway.addChild(headMicro)
        headMicro.setScale(Self.headScale)

        for side: CGFloat in [-1, 1] {
            let horn = SKSpriteNode(texture: textures.horn, size: DemonArtwork.hornSize)
            horn.anchorPoint = DemonArtwork.anchor(DemonArtwork.hornBase, in: DemonArtwork.hornSize)
            horn.position = CGPoint(x: side * 66, y: 104)
            horn.xScale = side > 0 ? -0.85 : 0.85
            horn.yScale = 0.85
            horn.zPosition = -2
            let glow = SKSpriteNode(texture: textures.hornGlow, size: DemonArtwork.hornSize)
            glow.anchorPoint = horn.anchorPoint
            glow.blendMode = .add
            glow.alpha = 0
            glow.zPosition = 0.1
            horn.addChild(glow)
            headMicro.addChild(horn)
            horns.append(horn)
            hornGlows.append(glow)

            let ear = SKSpriteNode(texture: textures.ear, size: DemonArtwork.earSize)
            ear.anchorPoint = DemonArtwork.anchor(DemonArtwork.earBase, in: DemonArtwork.earSize)
            ear.position = CGPoint(x: side * 104, y: 26)
            ear.xScale = side > 0 ? -1 : 1
            ear.zPosition = -1
            headMicro.addChild(ear)
            ears.append(ear)
        }

        head = SKSpriteNode(texture: textures.head, size: DemonArtwork.headSize)
        head.zPosition = 0
        headMicro.addChild(head)

        mouthGlow = glowSprite(textures.softDot, color: Palette.neonGreen, size: 180)
        mouthGlow.yScale = 0.5
        mouthGlow.position = CGPoint(x: 0, y: -98)
        mouthGlow.zPosition = 0.5
        headMicro.addChild(mouthGlow)

        mouth = SKSpriteNode(texture: textures.mouth, size: DemonArtwork.mouthSize)
        mouth.anchorPoint = DemonArtwork.anchor(DemonArtwork.mouthAnchor, in: DemonArtwork.mouthSize)
        mouth.position = CGPoint(x: 0, y: -88)
        mouth.zPosition = 1
        mouth.alpha = 0
        headMicro.addChild(mouth)

        for side: CGFloat in [-1, 1] {
            let eye = SKNode()
            eye.position = CGPoint(x: side * 46, y: 12)
            eye.xScale = side > 0 ? -1 : 1
            eye.zPosition = 2
            headMicro.addChild(eye)

            let glow = glowSprite(textures.softDot, color: Palette.neonGreen, size: 150)
            glow.alpha = 0
            glow.zPosition = -0.1
            eye.addChild(glow)

            let eyeAnchor = DemonArtwork.anchor(DemonArtwork.eyeCenter, in: DemonArtwork.eyeSize)
            let mask = SKSpriteNode(texture: textures.eyeMask, size: DemonArtwork.eyeSize)
            mask.anchorPoint = eyeAnchor
            let crop = SKCropNode()
            crop.maskNode = mask
            eye.addChild(crop)

            let eyeball = SKSpriteNode(texture: textures.eyeball, size: DemonArtwork.eyeSize)
            eyeball.anchorPoint = eyeAnchor
            crop.addChild(eyeball)

            let lid = SKSpriteNode(texture: textures.lid, size: DemonArtwork.lidSize)
            lid.anchorPoint = CGPoint(x: 0.5, y: 1 - DemonArtwork.lidEdgeY / DemonArtwork.lidSize.height)
            lid.position = CGPoint(x: -2, y: Self.lidClosedY)
            lid.zPosition = 1
            crop.addChild(lid)

            let brow = SKSpriteNode(texture: textures.brow, size: DemonArtwork.browSize)
            brow.anchorPoint = DemonArtwork.anchor(DemonArtwork.browCenter, in: DemonArtwork.browSize)
            brow.position = CGPoint(x: side * 54, y: 40)
            brow.xScale = side > 0 ? -1 : 1
            brow.zPosition = 4
            headMicro.addChild(brow)

            eyeGlows.append(glow)
            lids.append(lid)
            brows.append(brow)
        }

        embers = makeEmbers(texture: textures.spark)
        embers.position = CGPoint(x: 0, y: -40)
        embers.zPosition = 20
        root.addChild(embers)

        flamesGreen.targetNode = root
        flamesViolet.targetNode = root
        embers.targetNode = root

        dimmableSprites = [head, body] + horns + ears + brows
        applyAmbientSettings()
    }

    private func glowSprite(_ texture: SKTexture, color: UIColor, size: CGFloat) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
        sprite.color = color
        sprite.colorBlendFactor = 1
        sprite.blendMode = .add
        return sprite
    }

    private func makeFlames(texture: SKTexture, colors: [UIColor]) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = texture
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 1.7
        emitter.particleLifetimeRange = 0.8
        emitter.particlePositionRange = CGVector(dx: 470, dy: 50)
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = 0.35
        emitter.particleSpeed = 70
        emitter.particleSpeedRange = 40
        emitter.yAcceleration = 35
        emitter.particleAlpha = 0.5
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.3
        emitter.particleScale = 0.75
        emitter.particleScaleRange = 0.35
        emitter.particleScaleSpeed = 0.2
        emitter.particleRotationRange = 0.5
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: colors + [colors.last?.withAlphaComponent(0) ?? .clear],
            times: [0, 0.35, 0.7, 1])
        return emitter
    }

    private func makeEmbers(texture: SKTexture) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = texture
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 2.6
        emitter.particleLifetimeRange = 1.2
        emitter.particlePositionRange = CGVector(dx: 560, dy: 420)
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = 0.9
        emitter.particleSpeed = 30
        emitter.particleSpeedRange = 25
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -0.35
        emitter.particleScale = 0.55
        emitter.particleScaleRange = 0.35
        emitter.particleScaleSpeed = -0.1
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [Palette.neonGreen, Palette.green, Palette.violet],
            times: [0, 0.5, 1])
        return emitter
    }

    // MARK: - Layout

    /// Der Dämon wird so skaliert, dass Hörner und Kopf vollständig sichtbar
    /// sind; der Körper darf unten in den Nebel auslaufen.
    private func layoutFigure() {
        guard size.width > 0, size.height > 0 else { return }
        let designWidth: CGFloat = 640
        let designTop: CGFloat = 410
        let designBottom: CGFloat = -370
        let scale = min(size.width / designWidth, size.height / (designTop - designBottom))
        root.setScale(scale)
        let centerOffset = (designTop + designBottom) / 2 * scale
        root.position = CGPoint(x: size.width / 2, y: size.height / 2 - centerOffset)

        let fogPositions: [CGPoint] = [
            CGPoint(x: 0.15, y: 0.25), CGPoint(x: 0.85, y: 0.3), CGPoint(x: 0.5, y: 0.08),
            CGPoint(x: 0.3, y: 0.6), CGPoint(x: 0.75, y: 0.7),
        ]
        let fogSize = max(size.width, size.height) * 0.9
        for (index, fog) in fogSprites.enumerated() {
            let unit = fogPositions[index % fogPositions.count]
            fog.removeAllActions()
            fog.position = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
            fog.size = CGSize(width: fogSize, height: fogSize * 0.6)
        }
        applyAmbientSettings()
    }

    private func applyAmbientSettings() {
        guard isBuilt else { return }
        let animateFog = !renderSettings.reduceMotion && !renderSettings.reducedEffects
        for (index, fog) in fogSprites.enumerated() {
            fog.removeAction(forKey: "drift")
            guard animateFog else { continue }
            let distance = CGFloat(30 + index * 12)
            let duration = 9 + Double(index) * 2.5
            let drift = SKAction.sequence([
                SKAction.moveBy(x: distance, y: distance * 0.3, duration: duration),
                SKAction.moveBy(x: -distance, y: -distance * 0.3, duration: duration),
            ])
            drift.timingMode = .easeInEaseOut
            fog.run(.repeatForever(drift), withKey: "drift")
        }
        for fog in fogSprites {
            fog.alpha = renderSettings.reducedEffects ? 0.05 : 0.09
        }
    }

    // MARK: - Frame-Update

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt else { return }
        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.1) } ?? 1.0 / 60
        lastUpdateTime = currentTime
        clock += dt

        let frame = brain.update(input: inputProvider(), deltaTime: dt)
        currentFrame = frame
        apply(frame, dt: dt)

        if frame.mood != lastReportedMood || clock - lastReportTime >= 0.1 {
            if let previous = lastReportedMood, previous != frame.mood {
                moodChanged(from: previous, to: frame.mood)
            }
            lastReportedMood = frame.mood
            lastReportTime = clock
            onFrame?(frame)
        }
    }

    private func apply(_ frame: DemonFrame, dt: TimeInterval) {
        let settings = renderSettings
        let motion: Double = settings.reduceMotion ? 0.35 : 1
        let intensity = settings.animationIntensity
        let energy = frame.energy
        let mood = frame.mood

        // Atmung: tief und langsam im Schlaf, schneller und kräftiger, wenn entfesselt.
        let targetRate: Double = switch mood {
        case .disconnected, .engineOff: 0.16
        case .waitingForData, .idle: 0.2
        case .awakening: 0.26
        case .awake: 0.32
        case .unleashed: 0.48
        }
        breathRate += (targetRate - breathRate) * DemonBrain.blend(dt, 1.5)
        breathPhase += dt * 2 * .pi * breathRate
        let breath = sin(breathPhase)
        let breathDepth = (mood == .unleashed ? 1.4 : 1) * motion
        body.yScale = CGFloat(0.9 * (1 + 0.012 * breath * breathDepth))
        body.xScale = CGFloat(0.9 * (1 + 0.004 * breath * breathDepth))

        // Kopfhaltung, ruhiges Wiegen und leichtes Beben im entfesselten Zustand.
        let sleepiness = 1 - frame.headLift
        let swaySpeed = 0.35 + 0.5 * frame.headLift
        var sway = (0.02 + 0.015 * frame.headLift) * sin(clock * swaySpeed) * motion * intensity
        sway += -0.035 * sleepiness
        var jitterX: Double = 0
        if !settings.reduceMotion, mood == .unleashed {
            let tremor = max(0, energy - 0.7) / 0.3 * intensity
            sway += 0.006 * tremor * (sin(clock * 29) + sin(clock * 41 + 1.3)) / 2
            jitterX = 1.4 * tremor * sin(clock * 37 + 0.7)
        }
        headSway.zRotation = CGFloat(sway)
        let lift = -34 * sleepiness + 4 * breath * breathDepth + 10 * frame.surge * motion
        headLift.position = CGPoint(x: jitterX, y: lift)
        headMicro.setScale(Self.headScale * CGFloat(1 + 0.03 * frame.surge * motion))

        // Augen: Lider öffnen sich schrittweise; im Wachzustand gelegentliches Blinzeln.
        updateBlink(mood: mood, dt: dt)
        let blinkFactor = blinkRemaining > 0 ? max(0, 1 - sin(.pi * (1 - blinkRemaining / 0.16))) : 1
        let openness = frame.eyeOpenness * blinkFactor
        let glowStrength = settings.eyeGlowStrength
        let leak = mood == .awakening ? 0.15 * (1 - openness) : 0
        let eyeGlowAlpha = (openness * (0.35 + 0.65 * energy) + leak) * glowStrength
        let eyeGlowScale = 0.8 + 0.6 * energy + 0.3 * frame.surge
        for (index, lid) in lids.enumerated() {
            // Leicht asymmetrisch, damit die Figur lebendiger wirkt.
            let asymmetry = index == 0 ? 1.0 : 0.96
            lid.position.y = Self.lidClosedY + Self.lidTravel * CGFloat(min(1, openness * asymmetry))
        }
        for glow in eyeGlows {
            glow.alpha = CGFloat(eyeGlowAlpha)
            glow.setScale(CGFloat(eyeGlowScale))
        }

        // Brauen senken sich mit wachsender Energie zu einem grimmigen Blick.
        let browAnger = -0.05 + 0.26 * energy + 0.1 * frame.surge
        for (index, brow) in brows.enumerated() {
            let side: CGFloat = index == 0 ? -1 : 1
            brow.zRotation = side * CGFloat(browAnger)
            brow.position.y = 40 - 5 * CGFloat(energy)
        }

        // Maul: öffnet sich erst bei hoher Energie zu einem Fauchen.
        let snarl = min(1, Self.smoothstep(0.45, 0.85, energy) + 0.35 * frame.surge)
        mouth.alpha = CGFloat(snarl)
        mouth.xScale = 0.85
        mouth.yScale = CGFloat(0.5 + 0.5 * snarl)
        mouthGlow.alpha = CGFloat(snarl * 0.7 * glowStrength)

        // Hörner leuchten blau-violett mit der Energie.
        var hornAlpha = (0.12 + 0.88 * energy) * (0.5 + 0.5 * intensity)
        if mood == .disconnected || mood == .waitingForData {
            hornAlpha = 0.1 + 0.06 * (1 + sin(clock * 1.2)) * motion
        }
        hornGlows.forEach { $0.alpha = CGFloat(hornAlpha) }

        // Aura wächst mit der Drehzahl.
        let auraPulse = 0.04 * breath * motion
        auraInner.alpha = CGFloat(energy * 0.55 * intensity)
        auraInner.setScale(CGFloat(0.75 + 0.45 * energy + auraPulse + 0.2 * frame.surge))
        auraOuter.alpha = CGFloat((0.08 + 0.45 * energy) * intensity)
        auraOuter.setScale(CGFloat(0.85 + 0.3 * energy + auraPulse))

        // Partikel.
        let particleFactor = settings.particleStrength * (settings.reducedEffects ? 0.3 : 1)
        let flameEnergy = pow(max(0, energy - 0.05), 1.3)
        flamesGreen.particleBirthRate = CGFloat((flameEnergy * 55 + frame.surge * 40) * particleFactor)
        flamesViolet.particleBirthRate = CGFloat((0.1 + flameEnergy) * 45 * particleFactor)
        flamesGreen.particleSpeed = CGFloat(50 + 110 * energy)
        flamesViolet.particleSpeed = CGFloat(40 + 90 * energy)
        let emberRate = max(0, energy - 0.3) * 45 + frame.surge * 25
        embers.particleBirthRate = CGFloat(emberRate * particleFactor * (settings.reducedEffects ? 0.5 : 1))

        // Ohne Verbindung wirkt die Figur gedämpft und steinern.
        let targetDim: Double = switch mood {
        case .disconnected: 0.35
        case .waitingForData: 0.2
        default: 0
        }
        dimming += (targetDim - dimming) * DemonBrain.blend(dt, 0.8)
        for sprite in dimmableSprites {
            sprite.color = .black
            sprite.colorBlendFactor = CGFloat(dimming)
        }

        updateMicroMovements(mood: mood, dt: dt)
        updateSleepZ(mood: mood)
    }

    private func updateBlink(mood: DemonMood, dt: TimeInterval) {
        if blinkRemaining > 0 {
            blinkRemaining = max(0, blinkRemaining - dt)
            return
        }
        guard mood >= .awake else { return }
        nextBlink -= dt
        if nextBlink <= 0 {
            blinkRemaining = 0.16
            nextBlink = Double.random(in: 3...7)
        }
    }

    /// Gelegentliche kleine Bewegungen im Schlaf (Kopfneigen, Ohrzucken).
    private func updateMicroMovements(mood: DemonMood, dt: TimeInterval) {
        guard !renderSettings.reduceMotion else { return }
        nextMicroMovement -= dt
        guard nextMicroMovement <= 0 else { return }
        nextMicroMovement = Double.random(in: 5...10)
        switch mood {
        case .idle, .engineOff, .disconnected, .waitingForData:
            if Bool.random() {
                let angle = CGFloat.random(in: 0.02...0.045) * (Bool.random() ? 1 : -1)
                let tilt = SKAction.sequence([
                    SKAction.rotate(toAngle: angle, duration: 1.4),
                    SKAction.wait(forDuration: 1.2),
                    SKAction.rotate(toAngle: 0, duration: 1.6),
                ])
                tilt.timingMode = .easeInEaseOut
                headMicro.run(tilt, withKey: "micro")
            } else if let ear = ears.randomElement() {
                let twitch = SKAction.sequence([
                    SKAction.rotate(byAngle: 0.12, duration: 0.12),
                    SKAction.rotate(byAngle: -0.12, duration: 0.3),
                ])
                ear.run(twitch, withKey: "twitch")
            }
        case .awakening, .awake:
            let glance = SKAction.sequence([
                SKAction.moveBy(x: 6, y: 0, duration: 0.5),
                SKAction.wait(forDuration: 0.8),
                SKAction.moveBy(x: -6, y: 0, duration: 0.6),
            ])
            glance.timingMode = .easeInEaseOut
            headMicro.run(glance, withKey: "micro")
        case .unleashed:
            break
        }
    }

    /// Sanft aufsteigende „z“ im Schlaf.
    private func updateSleepZ(mood: DemonMood) {
        guard mood == .engineOff || mood == .idle else { return }
        guard clock >= nextZ else { return }
        nextZ = clock + (mood == .engineOff ? 2.2 : 3.2)
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = Bool.random() ? "z" : "Z"
        label.fontSize = CGFloat.random(in: 26...40)
        label.fontColor = Palette.blurple.withAlphaComponent(0.8)
        label.position = CGPoint(x: 150, y: 150)
        label.alpha = 0
        label.zPosition = 30
        root.addChild(label)
        let rise: CGFloat = renderSettings.reduceMotion ? 30 : 110
        let float = SKAction.group([
            SKAction.moveBy(x: 50, y: rise, duration: 3.2),
            SKAction.sequence([SKAction.fadeAlpha(to: 0.85, duration: 0.6), SKAction.wait(forDuration: 1.4),
                               SKAction.fadeOut(withDuration: 1.2)]),
            SKAction.scale(to: 1.35, duration: 3.2),
        ])
        float.timingMode = .easeOut
        label.run(.sequence([float, .removeFromParent()]))
    }

    private func moodChanged(from old: DemonMood, to new: DemonMood) {
        if new > old, new >= .awake, !renderSettings.reduceMotion {
            // Kurzes, weiches Aufbäumen der Aura – kein Blitzen.
            let swell = SKAction.sequence([
                SKAction.scale(by: 1.12, duration: 0.3),
                SKAction.scale(by: 1 / 1.12, duration: 0.6),
            ])
            swell.timingMode = .easeInEaseOut
            auraNode.run(swell, withKey: "swell")
        }
        if new < .awake {
            blinkRemaining = 0
        }
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }
}
