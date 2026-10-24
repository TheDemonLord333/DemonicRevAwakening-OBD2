//
//  DemonBrain.swift
//  DemonicRevAwakening OBD2
//
//  Zustandslogik des Dämons: Glättung, Hysterese, kontinuierliche Energie
//  und kurze Reaktionen auf schnelle Drehzahlanstiege. Unabhängig vom
//  Rendering und vom Abfragetakt – wird pro Animationsframe aufgerufen.
//

import Foundation

nonisolated enum DemonMood: Int, CaseIterable, Comparable, Sendable {
    case disconnected
    case waitingForData
    case engineOff
    case idle
    case awakening
    case awake
    case unleashed

    static func < (lhs: DemonMood, rhs: DemonMood) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Kurzer Status für die Oberfläche.
    var title: String {
        switch self {
        case .disconnected: "Wartet auf Verbindung"
        case .waitingForData: "Wartet auf Daten"
        case .engineOff: "Schläft tief"
        case .idle: "Schläft"
        case .awakening: "Erwacht"
        case .awake: "Wach"
        case .unleashed: "Entfesselt"
        }
    }

    var detail: String {
        switch self {
        case .disconnected: "Verbinde einen OBD2-Adapter oder starte die Demo."
        case .waitingForData: "Verbunden – es liegt keine aktuelle Drehzahl vor."
        case .engineOff: "Motor aus (0 RPM empfangen)."
        case .idle: "Leerlauf – ruhiger Atem."
        case .awakening: "Die Augen öffnen sich."
        case .awake: "Hellwach und lauernd."
        case .unleashed: "Volle dämonische Energie."
        }
    }

    /// Zustände, die aus einer gültigen Drehzahl abgeleitet werden.
    var isDrivenByRPM: Bool { self >= .engineOff }
}

/// Ergebnis eines Logik-Schritts, das der Renderer darstellt.
nonisolated struct DemonFrame: Equatable, Sendable {
    var mood: DemonMood
    /// Geglättete Drehzahl für Anzeigen; `nil`, wenn keine gültigen Daten.
    var smoothedRPM: Double?
    /// Kontinuierliche Energie 0 … 1, aus der Drehzahl berechnet.
    var energy: Double
    /// Augenöffnung 0 (geschlossen) … 1 (offen).
    var eyeOpenness: Double
    /// Kopfhaltung 0 (gesenkt, schlafend) … 1 (aufgerichtet).
    var headLift: Double
    /// Kurzzeitige Reaktion auf einen schnellen Drehzahlanstieg, 0 … 1.
    var surge: Double

    static let resting = DemonFrame(mood: .disconnected, smoothedRPM: nil, energy: 0,
                                    eyeOpenness: 0, headLift: 0.2, surge: 0)
}

nonisolated struct DemonBrain {
    var thresholds: RPMThresholds

    /// Gesamtbreite des Hysteresebands um jede Schwelle (RPM).
    var hysteresis: Double = 160
    /// Mindestdauer, die ein neuer Zustand anliegen muss, bevor gewechselt wird.
    var dwellTime: TimeInterval = 0.45
    /// Unterhalb dieses Werts gilt der Motor als aus (Animationsdetail).
    static let engineOffBelow: Double = 250

    // Zeitkonstanten der Glättung (Sekunden).
    var rpmRiseTau: TimeInterval = 0.2
    var rpmFallTau: TimeInterval = 0.75
    var eyeOpenTau: TimeInterval = 0.35
    var eyeCloseTau: TimeInterval = 1.4
    var energyRiseTau: TimeInterval = 0.3
    var energyFallTau: TimeInterval = 1.0
    var liftTau: TimeInterval = 0.6
    var surgeDecayTau: TimeInterval = 0.45

    /// Mindestanstieg (RPM/s) und Mindestdifferenz für eine Kurzreaktion.
    var surgeRateThreshold: Double = 2_500
    var surgeDeltaThreshold: Double = 400
    var surgeCooldown: TimeInterval = 1.5

    private(set) var mood: DemonMood = .disconnected
    private(set) var smoothedRPM: Double?
    private(set) var energy: Double = 0
    private(set) var eyeOpenness: Double = 0
    private(set) var headLift: Double = 0.2
    private(set) var surge: Double = 0

    private var clock: TimeInterval = 0
    private var pendingMood: DemonMood?
    private var pendingSince: TimeInterval = 0
    private var windowStartRPM: Double?
    private var windowStartTime: TimeInterval = 0
    private var surgeBlockedUntil: TimeInterval = 0

    init(thresholds: RPMThresholds = .standard) {
        self.thresholds = thresholds.normalized()
    }

    var frame: DemonFrame {
        DemonFrame(mood: mood, smoothedRPM: smoothedRPM, energy: min(1, energy + 0.25 * surge),
                   eyeOpenness: eyeOpenness, headLift: headLift, surge: surge)
    }

    @discardableResult
    mutating func update(input: DemonInput, deltaTime: TimeInterval) -> DemonFrame {
        // Große Sprünge (z. B. nach Rückkehr aus dem Hintergrund) begrenzen.
        let dt = min(max(deltaTime, 0), 0.25)
        clock += dt

        switch input {
        case .noConnection:
            resetSignal()
            setMoodImmediately(.disconnected)
        case .awaitingData:
            resetSignal()
            setMoodImmediately(.waitingForData)
        case .rpm(let rawValue):
            let rpm = max(0, rawValue.isFinite ? rawValue : 0)
            detectSurge(rpm: rpm)
            let smoothed: Double
            if let previous = smoothedRPM {
                let tau = rpm > previous ? rpmRiseTau : rpmFallTau
                smoothed = previous + (rpm - previous) * Self.blend(dt, tau)
            } else {
                smoothed = rpm
            }
            smoothedRPM = smoothed
            let candidate = level(for: smoothed)
            if mood.isDrivenByRPM {
                applyWithDwell(candidate)
            } else {
                // Erste gültige Daten nach Verbindungsaufbau sofort zeigen.
                setMoodImmediately(candidate)
            }
        }

        updateTargets(dt: dt)
        return frame
    }

    // MARK: - Zustandsbestimmung

    /// Drehzahlstufe mit Hysterese relativ zum aktuellen Zustand.
    func level(for rpm: Double) -> DemonMood {
        let levels: [DemonMood] = [.engineOff, .idle, .awakening, .awake, .unleashed]
        let boundaries = [Self.engineOffBelow, thresholds.awakeningStart,
                          thresholds.awakeStart, thresholds.unleashedStart]
        // Am Übergang Motor aus/Leerlauf genügt ein schmaleres Band.
        let halfBands = [min(60, hysteresis / 2), hysteresis / 2, hysteresis / 2, hysteresis / 2]

        guard mood.isDrivenByRPM, let start = levels.firstIndex(of: mood) else {
            let index = boundaries.filter { rpm >= $0 }.count
            return levels[index]
        }
        var index = start
        while index < boundaries.count, rpm >= boundaries[index] + halfBands[index] {
            index += 1
        }
        while index > 0, rpm < boundaries[index - 1] - halfBands[index - 1] {
            index -= 1
        }
        return levels[index]
    }

    private mutating func applyWithDwell(_ candidate: DemonMood) {
        guard candidate != mood else {
            pendingMood = nil
            return
        }
        if pendingMood != candidate {
            pendingMood = candidate
            pendingSince = clock
        }
        if clock - pendingSince >= dwellTime - 1e-9 {
            mood = candidate
            pendingMood = nil
        }
    }

    private mutating func setMoodImmediately(_ newMood: DemonMood) {
        mood = newMood
        pendingMood = nil
    }

    private mutating func resetSignal() {
        smoothedRPM = nil
        windowStartRPM = nil
    }

    // MARK: - Kurzreaktion

    private mutating func detectSurge(rpm: Double) {
        guard let startRPM = windowStartRPM else {
            windowStartRPM = rpm
            windowStartTime = clock
            return
        }
        let elapsed = clock - windowStartTime
        guard elapsed >= 0.2 else { return }
        let delta = rpm - startRPM
        let rate = delta / elapsed
        if mood >= .idle, delta >= surgeDeltaThreshold, rate >= surgeRateThreshold, clock >= surgeBlockedUntil {
            surge = 1
            surgeBlockedUntil = clock + surgeCooldown
        }
        windowStartRPM = rpm
        windowStartTime = clock
    }

    // MARK: - Kontinuierliche Größen

    /// Energie 0 … 1 als stückweise lineare Funktion der Drehzahl.
    func energy(forRPM rpm: Double) -> Double {
        let t = thresholds
        let anchors: [(Double, Double)] = [
            (0, 0),
            (Self.engineOffBelow, 0.02),
            (t.awakeningStart, 0.12),
            (t.awakeStart, 0.42),
            (t.unleashedStart, 0.72),
            (t.scaleMax, 1),
        ]
        if rpm <= 0 { return 0 }
        for index in 1..<anchors.count {
            let (x1, y1) = anchors[index]
            let (x0, y0) = anchors[index - 1]
            if rpm <= x1 {
                let span = max(x1 - x0, 1)
                return y0 + (y1 - y0) * (rpm - x0) / span
            }
        }
        return 1
    }

    /// Fortschritt innerhalb des Bereichs „Erwachend“, 0 … 1.
    func awakeningProgress(forRPM rpm: Double) -> Double {
        let span = max(thresholds.awakeStart - thresholds.awakeningStart, 1)
        return ((rpm - thresholds.awakeningStart) / span).clamped(to: 0...1)
    }

    private mutating func updateTargets(dt: TimeInterval) {
        let rpm = smoothedRPM ?? 0
        let targetEnergy: Double
        let targetEyes: Double
        let targetLift: Double

        switch mood {
        case .disconnected:
            targetEnergy = 0
            targetEyes = 0
            targetLift = 0.25
        case .waitingForData:
            targetEnergy = 0.03
            targetEyes = 0.12
            targetLift = 0.3
        case .engineOff:
            targetEnergy = energy(forRPM: rpm)
            targetEyes = 0
            targetLift = 0
        case .idle:
            targetEnergy = energy(forRPM: rpm)
            targetEyes = 0
            targetLift = 0.12
        case .awakening:
            let progress = awakeningProgress(forRPM: rpm)
            targetEnergy = energy(forRPM: rpm)
            targetEyes = 0.2 + 0.65 * progress
            targetLift = 0.35 + 0.4 * progress
        case .awake:
            targetEnergy = energy(forRPM: rpm)
            targetEyes = 1
            targetLift = 0.88
        case .unleashed:
            targetEnergy = energy(forRPM: rpm)
            targetEyes = 1
            targetLift = 1
        }

        energy += (targetEnergy - energy) * Self.blend(dt, targetEnergy > energy ? energyRiseTau : energyFallTau)
        eyeOpenness += (targetEyes - eyeOpenness) * Self.blend(dt, targetEyes > eyeOpenness ? eyeOpenTau : eyeCloseTau)
        headLift += (targetLift - headLift) * Self.blend(dt, liftTau)
        surge *= exp(-dt / surgeDecayTau)
        if surge < 0.001 { surge = 0 }
    }

    /// Anteil, um den sich ein Wert in `dt` einem Ziel annähert (exponentiell).
    static func blend(_ dt: TimeInterval, _ tau: TimeInterval) -> Double {
        guard tau > 0 else { return 1 }
        return 1 - exp(-dt / tau)
    }
}
