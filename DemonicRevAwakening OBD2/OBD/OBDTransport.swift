//
//  OBDTransport.swift
//  DemonicRevAwakening OBD2
//
//  Gemeinsame Schnittstelle für BLE-, WLAN- und Test-Transporte.
//  Ein Transport überträgt nur Bytes; die ELM327-Logik liegt in `OBDSession`.
//

import Foundation

protocol OBDTransport: AnyObject {
    /// Anzeigename, z. B. „OBDLink CX“ oder „192.168.0.10:35000“.
    var displayName: String { get }
    /// Empfangene Bytes (auf dem MainActor).
    var onReceive: ((Data) -> Void)? { get set }
    /// Verbindung wurde unerwartet oder durch `close()` beendet.
    var onClose: ((Error?) -> Void)? { get set }

    /// Baut die Verbindung auf und wirft bei Fehlern.
    func open() async throws
    /// Sendet Bytes unter Beachtung der Flusskontrolle des Transports.
    func write(_ data: Data) async throws
    /// Trennt die Verbindung. Mehrfache Aufrufe sind erlaubt.
    func close()
}

/// Fehler der Transportschicht mit verständlichen Meldungen.
nonisolated enum TransportError: LocalizedError, Equatable, Sendable {
    case bluetoothUnavailable(String)
    case deviceNotFound
    case connectionTimeout
    case connectionFailed(String)
    case serviceNotFound(profile: String)
    case characteristicNotFound(String)
    case characteristicNotUsable(String)
    case notificationsFailed(String)
    case writeFailed(String)
    case disconnected(String?)
    case invalidEndpoint
    case networkWaiting(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let reason):
            return reason
        case .deviceNotFound:
            return "Das Bluetooth-Gerät wurde nicht gefunden. Ist der Adapter eingesteckt und eingeschaltet?"
        case .connectionTimeout:
            return "Zeitüberschreitung beim Verbindungsaufbau."
        case .connectionFailed(let reason):
            return "Verbindung fehlgeschlagen: \(reason)"
        case .serviceNotFound(let profile):
            return "Das Gerät bietet den Dienst des Profils „\(profile)“ nicht an. Es ist mit diesem Profil nicht kompatibel."
        case .characteristicNotFound(let uuid):
            return "Characteristic \(uuid) wurde nicht gefunden – Profil passt nicht zum Gerät."
        case .characteristicNotUsable(let reason):
            return reason
        case .notificationsFailed(let reason):
            return "Benachrichtigungen konnten nicht aktiviert werden: \(reason)"
        case .writeFailed(let reason):
            return "Senden fehlgeschlagen: \(reason)"
        case .disconnected(let reason):
            return reason.map { "Verbindung getrennt: \($0)" } ?? "Verbindung getrennt."
        case .invalidEndpoint:
            return "Ungültige IP-Adresse oder ungültiger Port."
        case .networkWaiting(let reason):
            return "Keine Verbindung zum WLAN-Adapter (\(reason)). Ist das iPhone mit dem WLAN des Adapters verbunden und der Zugriff auf das lokale Netzwerk erlaubt?"
        case .notConnected:
            return "Keine Verbindung."
        }
    }
}
