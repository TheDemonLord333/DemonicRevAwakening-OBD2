//
//  Settings.swift
//  DemonicRevAwakening OBD2
//
//  Persistierbare Einstellungen. Reine Werttypen ohne UI-Abhängigkeit.
//

import Foundation

/// Drehzahlschwellen, ab denen der Dämon seinen Zustand wechselt.
///
/// Diese Werte sind ausschließlich Animationsschwellen – keine empfohlenen
/// Drehzahlen und keine Motorschutzgrenzen.
nonisolated struct RPMThresholds: Codable, Equatable, Sendable {
    /// Ab dieser Drehzahl beginnt der Dämon zu erwachen (darunter: Leerlauf).
    var awakeningStart: Double = 1_000
    /// Ab dieser Drehzahl ist der Dämon wach.
    var awakeStart: Double = 2_000
    /// Ab dieser Drehzahl ist der Dämon entfesselt.
    var unleashedStart: Double = 3_500
    /// Endwert des Drehzahlmessers und der Energieskala.
    var scaleMax: Double = 8_000

    static let standard = RPMThresholds()

    /// Mindestabstand zwischen zwei benachbarten Schwellen.
    static let minimumGap: Double = 200
    /// Untergrenze für „Erwachend ab“ – darunter liegt der Bereich „Motor aus“.
    static let lowestAwakeningStart: Double = 500
    /// Erlaubter Bereich für das Skalenende.
    static let scaleRange: ClosedRange<Double> = 4_000...12_000

    /// Verständliche Beschreibung aller Verstöße gegen die Reihenfolge.
    var validationIssues: [String] {
        var issues: [String] = []
        let gap = Self.minimumGap
        if awakeningStart < Self.lowestAwakeningStart {
            issues.append("„Erwachend ab“ muss mindestens \(Int(Self.lowestAwakeningStart)) RPM betragen.")
        }
        if awakeStart - awakeningStart < gap {
            issues.append("„Wach ab“ muss mindestens \(Int(gap)) RPM über „Erwachend ab“ liegen.")
        }
        if unleashedStart - awakeStart < gap {
            issues.append("„Entfesselt ab“ muss mindestens \(Int(gap)) RPM über „Wach ab“ liegen.")
        }
        if scaleMax - unleashedStart < gap {
            issues.append("Das Skalenende muss mindestens \(Int(gap)) RPM über „Entfesselt ab“ liegen.")
        }
        if !Self.scaleRange.contains(scaleMax) {
            issues.append("Das Skalenende muss zwischen \(Int(Self.scaleRange.lowerBound)) und \(Int(Self.scaleRange.upperBound)) RPM liegen.")
        }
        return issues
    }

    var isValid: Bool { validationIssues.isEmpty }

    /// Erzwingt eine gültige, aufsteigende Reihenfolge und verändert dabei
    /// nur Werte, die tatsächlich gegen eine Regel verstoßen.
    func normalized() -> RPMThresholds {
        let gap = Self.minimumGap
        var result = self
        result.scaleMax = min(max(result.scaleMax, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        result.awakeningStart = min(max(result.awakeningStart, Self.lowestAwakeningStart), result.scaleMax - 3 * gap)
        result.awakeStart = min(max(result.awakeStart, result.awakeningStart + gap), result.scaleMax - 2 * gap)
        result.unleashedStart = min(max(result.unleashedStart, result.awakeStart + gap), result.scaleMax - gap)
        return result
    }
}

/// Art der zuletzt verwendeten Live-Verbindung.
nonisolated enum ConnectionKind: String, Codable, Sendable, CaseIterable {
    case bluetooth
    case wifi
}

/// Alle lokal gespeicherten Einstellungen der App.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    var thresholds = RPMThresholds.standard
    /// Gesamtintensität der Animation (Bewegung, Aura), 0.2 … 1.
    var animationIntensity: Double = 0.85
    /// Stärke des Augenleuchtens, 0 … 1.
    var eyeGlowStrength: Double = 0.9
    /// Stärke der Energiepartikel, 0 … 1.
    var particleStrength: Double = 0.75
    /// Reduziert Partikel, Nebel und Zusatzeffekte deutlich.
    var reducedEffects = false
    /// Hält das Display während einer aktiven Sitzung eingeschaltet.
    var keepScreenOn = true
    /// Versucht nach einem Verbindungsabbruch automatisch, neu zu verbinden.
    var autoReconnect = true

    var lastConnectionKind: ConnectionKind?
    var lastBLEProfileID: String?
    var lastBLEPeripheralID: UUID?
    var lastBLEPeripheralName: String?
    var wifiHost = "192.168.0.10"
    var wifiPort = 35_000
    var customBLEProfile = BLEAdapterProfile.customTemplate

    static let standard = AppSettings()

    static let intensityRange: ClosedRange<Double> = 0.2...1
    static let unitRange: ClosedRange<Double> = 0...1

    init() {}

    /// Setzt Darstellung und Schwellen zurück, behält aber Verbindungsdaten.
    func resettingAppearance() -> AppSettings {
        var result = AppSettings.standard
        result.lastConnectionKind = lastConnectionKind
        result.lastBLEProfileID = lastBLEProfileID
        result.lastBLEPeripheralID = lastBLEPeripheralID
        result.lastBLEPeripheralName = lastBLEPeripheralName
        result.wifiHost = wifiHost
        result.wifiPort = wifiPort
        result.customBLEProfile = customBLEProfile
        return result
    }

    /// Klemmt alle Werte auf gültige Bereiche.
    func sanitized() -> AppSettings {
        var result = self
        result.thresholds = thresholds.normalized()
        result.animationIntensity = animationIntensity.clamped(to: Self.intensityRange)
        result.eyeGlowStrength = eyeGlowStrength.clamped(to: Self.unitRange)
        result.particleStrength = particleStrength.clamped(to: Self.unitRange)
        if !WiFiEndpointValidator.isValidPort(result.wifiPort) {
            result.wifiPort = AppSettings.standard.wifiPort
        }
        return result
    }

    // Tolerantes Decoding: fehlende Schlüssel (z. B. nach App-Updates)
    // fallen auf Standardwerte zurück, statt alle Einstellungen zu verwerfen.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.standard
        thresholds = try container.decodeIfPresent(RPMThresholds.self, forKey: .thresholds) ?? defaults.thresholds
        animationIntensity = try container.decodeIfPresent(Double.self, forKey: .animationIntensity) ?? defaults.animationIntensity
        eyeGlowStrength = try container.decodeIfPresent(Double.self, forKey: .eyeGlowStrength) ?? defaults.eyeGlowStrength
        particleStrength = try container.decodeIfPresent(Double.self, forKey: .particleStrength) ?? defaults.particleStrength
        reducedEffects = try container.decodeIfPresent(Bool.self, forKey: .reducedEffects) ?? defaults.reducedEffects
        keepScreenOn = try container.decodeIfPresent(Bool.self, forKey: .keepScreenOn) ?? defaults.keepScreenOn
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? defaults.autoReconnect
        lastConnectionKind = try container.decodeIfPresent(ConnectionKind.self, forKey: .lastConnectionKind)
        lastBLEProfileID = try container.decodeIfPresent(String.self, forKey: .lastBLEProfileID)
        lastBLEPeripheralID = try container.decodeIfPresent(UUID.self, forKey: .lastBLEPeripheralID)
        lastBLEPeripheralName = try container.decodeIfPresent(String.self, forKey: .lastBLEPeripheralName)
        wifiHost = try container.decodeIfPresent(String.self, forKey: .wifiHost) ?? defaults.wifiHost
        wifiPort = try container.decodeIfPresent(Int.self, forKey: .wifiPort) ?? defaults.wifiPort
        customBLEProfile = try container.decodeIfPresent(BLEAdapterProfile.self, forKey: .customBLEProfile) ?? defaults.customBLEProfile
    }
}

/// Prüfung der WLAN-Verbindungsdaten.
nonisolated enum WiFiEndpointValidator {
    static func isValidPort(_ port: Int) -> Bool { (1...65_535).contains(port) }

    /// Akzeptiert IPv4-Adressen und einfache Hostnamen ohne Leerzeichen.
    static func isValidHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 253 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ $0.allSatisfy(\.isNumber) && !$0.isEmpty }) {
            return parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
        }
        return !trimmed.hasPrefix(".") && !trimmed.hasSuffix(".")
    }

    static func validationMessage(host: String, port: Int) -> String? {
        if !isValidHost(host) { return "Bitte eine gültige IP-Adresse oder einen Hostnamen eingeben." }
        if !isValidPort(port) { return "Der Port muss zwischen 1 und 65535 liegen." }
        return nil
    }
}

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
