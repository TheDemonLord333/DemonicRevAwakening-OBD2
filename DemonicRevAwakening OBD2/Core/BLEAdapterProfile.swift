//
//  BLEAdapterProfile.swift
//  DemonicRevAwakening OBD2
//
//  Beschreibt, über welche GATT-Dienste ein BLE-OBD2-Adapter seine
//  serielle ELM327-Schnittstelle anbietet. Bewusst ohne CoreBluetooth,
//  damit Profile testbar und speicherbar bleiben.
//

import Foundation

nonisolated struct BLEAdapterProfile: Codable, Hashable, Identifiable, Sendable {
    /// Gewünschter Schreibmodus für die Write-Characteristic.
    nonisolated enum WritePreference: String, Codable, Hashable, Sendable, CaseIterable {
        /// Ohne Antwort, falls die Characteristic es erlaubt, sonst mit Antwort.
        case automatic
        case withResponse
        case withoutResponse

        var title: String {
            switch self {
            case .automatic: "Automatisch"
            case .withResponse: "Mit Antwort (Write Request)"
            case .withoutResponse: "Ohne Antwort (Write Command)"
            }
        }
    }

    var id: String
    var name: String
    var serviceUUID: String
    var notifyCharacteristicUUID: String
    var writeCharacteristicUUID: String
    var writePreference: WritePreference
    /// Gerätenamen-Präfixe, die einen Hinweis (keinen Beweis) auf das Profil geben.
    var namePrefixes: [String]
    /// Herkunft der UUIDs.
    var documentationSource: String
    var isCustom: Bool

    var isValid: Bool { validationIssues.isEmpty }

    var validationIssues: [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Bitte einen Namen für das Profil angeben.")
        }
        if !BLEUUIDValidator.isValid(serviceUUID) {
            issues.append("Service-UUID ist ungültig.")
        }
        if !BLEUUIDValidator.isValid(notifyCharacteristicUUID) {
            issues.append("Notify-Characteristic-UUID ist ungültig.")
        }
        if !BLEUUIDValidator.isValid(writeCharacteristicUUID) {
            issues.append("Write-Characteristic-UUID ist ungültig.")
        }
        return issues
    }

    /// Prüft, ob ein beworbener Dienst zu diesem Profil passt.
    func matchesAdvertisedService(_ uuid: String) -> Bool {
        BLEUUIDValidator.canonical(uuid) == BLEUUIDValidator.canonical(serviceUUID)
    }

    func nameSuggestsProfile(_ deviceName: String?) -> Bool {
        guard let deviceName, !namePrefixes.isEmpty else { return false }
        let lower = deviceName.lowercased()
        return namePrefixes.contains { lower.hasPrefix($0.lowercased()) }
    }

    // MARK: - Mitgelieferte Profile

    /// OBDLink CX (OBD Solutions / ScanTool.net). Einziger BLE-Adapter der
    /// OBDLink-Familie. UUIDs laut „OBDLink CX Adapter Notes“ des Herstellers:
    /// Dienst FFF0, Notify FFF1, Write/Write without response FFF2.
    static let obdLinkCX = BLEAdapterProfile(
        id: "obdlink-cx",
        name: "OBDLink CX",
        serviceUUID: "FFF0",
        notifyCharacteristicUUID: "FFF1",
        writeCharacteristicUUID: "FFF2",
        writePreference: .automatic,
        namePrefixes: ["OBDLink CX"],
        documentationSource: "OBDLink CX Adapter Notes – support.obdlink.com/support/solutions/articles/43000746707",
        isCustom: false
    )

    /// Vorlage für ein manuell konfiguriertes Profil (Erweiterte Einstellungen).
    /// Leer, damit keine UUIDs erfunden werden.
    static let customTemplate = BLEAdapterProfile(
        id: "custom",
        name: "Eigenes Profil",
        serviceUUID: "",
        notifyCharacteristicUUID: "",
        writeCharacteristicUUID: "",
        writePreference: .automatic,
        namePrefixes: [],
        documentationSource: "Manuell eingetragen",
        isCustom: true
    )

    static let builtIn: [BLEAdapterProfile] = [.obdLinkCX]

    /// Alle verwendbaren Profile: mitgelieferte plus gültiges eigenes Profil.
    static func available(custom: BLEAdapterProfile) -> [BLEAdapterProfile] {
        custom.isValid ? builtIn + [custom] : builtIn
    }
}

/// Validiert UUID-Zeichenketten, bevor sie an CoreBluetooth gehen
/// (`CBUUID(string:)` bricht bei ungültigen Werten das Programm ab).
nonisolated enum BLEUUIDValidator {
    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        switch trimmed.count {
        case 4, 8:
            return trimmed.unicodeScalars.allSatisfy { hexDigits.contains($0) }
        case 36:
            return UUID(uuidString: trimmed) != nil
        default:
            return false
        }
    }

    /// Einheitliche Großschreibung; 16-/32-Bit-Kurzformen werden auf die
    /// Bluetooth-Basis-UUID erweitert, damit Kurz- und Langform vergleichbar sind.
    static func canonical(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces).uppercased()
        switch trimmed.count {
        case 4: return "0000\(trimmed)-0000-1000-8000-00805F9B34FB"
        case 8: return "\(trimmed)-0000-1000-8000-00805F9B34FB"
        default: return trimmed
        }
    }
}
