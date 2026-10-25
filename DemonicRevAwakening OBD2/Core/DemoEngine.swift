//
//  DemoEngine.swift
//  DemonicRevAwakening OBD2
//
//  Simulierte Fahrzeugdaten für den Demo-Modus. Die Werte durchlaufen
//  dieselbe Dämonen-Logik wie Live-Daten, sind aber stets als Demo markiert.
//

import Foundation

nonisolated struct DemoEngine: Sendable {
    nonisolated enum Mode: String, CaseIterable, Sendable {
        case automatic
        case manual

        var title: String {
            switch self {
            case .automatic: "Automatisch"
            case .manual: "Manuell"
            }
        }
    }

    static let rpmRange: ClosedRange<Double> = 0...8_000
    /// Dauer eines vollständigen Demo-Durchlaufs in Sekunden.
    static let scenarioDuration: TimeInterval = 44

    var mode: Mode = .automatic
    /// Zielwert des Schiebereglers im manuellen Modus.
    var manualTargetRPM: Double = 800 {
        didSet { manualTargetRPM = manualTargetRPM.clamped(to: Self.rpmRange) }
    }

    private(set) var isPaused = false
    private(set) var scenarioTime: TimeInterval = 0
    private(set) var rpm: Double = 0
    private(set) var speedKmh: Double = 0
    private(set) var engineLoadPercent: Double = 0

    /// Phase des automatischen Ablaufs für die Anzeige.
    var phaseDescription: String {
        guard mode == .automatic else { return "Manuelle Drehzahl" }
        switch scenarioTime {
        case ..<2.6: return "Motor aus"
        case ..<5.5: return "Motorstart"
        case ..<12: return "Leerlauf"
        case ..<14.5: return "Gasstoß"
        case ..<28: return "Drehzahlanstieg"
        case ..<36: return "Beruhigung"
        case ..<40.5: return "Leerlauf"
        default: return "Motor aus"
        }
    }

    mutating func advance(by deltaTime: TimeInterval) {
        guard !isPaused else { return }
        let dt = min(max(deltaTime, 0), 0.5)
        let previousRPM = rpm
        switch mode {
        case .automatic:
            scenarioTime = (scenarioTime + dt).truncatingRemainder(dividingBy: Self.scenarioDuration)
            rpm = Self.scenarioRPM(at: scenarioTime)
        case .manual:
            // Leichte Trägheit, damit der Regler wie ein Motor reagiert.
            let blend = 1 - exp(-dt / 0.25)
            rpm += (manualTargetRPM - rpm) * blend
            if abs(rpm - manualTargetRPM) < 0.5 { rpm = manualTargetRPM }
        }
        updateDerivedValues(previousRPM: previousRPM, dt: dt)
    }

    mutating func pause() { isPaused = true }
    mutating func resume() { isPaused = false }

    mutating func restart() {
        scenarioTime = 0
        rpm = mode == .automatic ? Self.scenarioRPM(at: 0) : manualTargetRPM
        speedKmh = 0
        engineLoadPercent = 0
        isPaused = false
    }

    mutating func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .manual { manualTargetRPM = rpm.rounded() }
    }

    // MARK: - Drehbuch

    private static let keyframes: [(time: TimeInterval, rpm: Double)] = [
        (0, 0), (2.6, 0),
        (2.9, 260), (3.4, 240),        // Anlasser
        (3.9, 1_350), (5.5, 860),      // Startdrehzahl, fällt auf Leerlauf
        (12, 800),
        (12.35, 3_100), (13.3, 1_150), (14.5, 900),   // kurzer Gasstoß
        (16, 1_400), (18, 2_100), (20, 2_900), (21, 3_100),
        (21.6, 2_300),                  // kurzer Abfall, ausdrücklich kein erkannter Gangwechsel
        (23, 3_400), (24.5, 4_300), (26, 5_600), (28, 5_900),
        (29.5, 4_000), (31.5, 2_400), (33.5, 1_500), (36, 830),
        (40.5, 800), (41.2, 0), (44, 0),
    ]

    /// Drehzahl des automatischen Ablaufs zum Zeitpunkt `time`.
    static func scenarioRPM(at time: TimeInterval) -> Double {
        let t = time.truncatingRemainder(dividingBy: scenarioDuration)
        guard let upperIndex = keyframes.firstIndex(where: { $0.time >= t }), upperIndex > 0 else {
            return keyframes.first?.rpm ?? 0
        }
        let lower = keyframes[upperIndex - 1]
        let upper = keyframes[upperIndex]
        let span = max(upper.time - lower.time, 0.0001)
        let x = ((t - lower.time) / span).clamped(to: 0...1)
        let eased = x * x * (3 - 2 * x)
        var value = lower.rpm + (upper.rpm - lower.rpm) * eased
        // Lebendiger Leerlauf: leichte, langsame Schwankung.
        if (600...1_000).contains(value) {
            value += 18 * sin(t * 2.1) + 9 * sin(t * 5.3)
        }
        return max(0, value)
    }

    private mutating func updateDerivedValues(previousRPM: Double, dt: TimeInterval) {
        // Grobe, klar simulierte Begleitwerte für die Zusatzanzeigen.
        let targetSpeed: Double
        if mode == .automatic {
            switch scenarioTime {
            case 16..<36: targetSpeed = ((rpm - 900) / 38).clamped(to: 0...150)
            default: targetSpeed = 0
            }
        } else {
            targetSpeed = ((rpm - 1_000) / 45).clamped(to: 0...150)
        }
        speedKmh += (targetSpeed - speedKmh) * (1 - exp(-dt / 1.2))

        let rate = dt > 0 ? (rpm - previousRPM) / dt : 0
        let baseLoad = rpm < Double(DemonBrain.engineOffBelow) ? 0 : 18 + 45 * (rpm / 6_000)
        let targetLoad = (baseLoad + max(0, rate) / 60).clamped(to: 0...100)
        engineLoadPercent += (targetLoad - engineLoadPercent) * (1 - exp(-dt / 0.3))
    }
}
