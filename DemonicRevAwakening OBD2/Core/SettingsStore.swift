//
//  SettingsStore.swift
//  DemonicRevAwakening OBD2
//
//  Speichert `AppSettings` lokal in den UserDefaults (kein Backend, keine Cloud).
//

import Foundation
import Observation

@Observable
final class SettingsStore {
    static let storageKey = "demonicRevAwakening.settings.v1"

    var settings: AppSettings {
        didSet {
            let sanitized = settings.sanitized()
            if sanitized != settings {
                settings = sanitized
                return
            }
            save()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded.sanitized()
        } else {
            settings = .standard
        }
    }

    /// Setzt Schwellen und Darstellung auf Standardwerte zurück.
    /// Verbindungsdaten (WLAN, Adapter, eigenes Profil) bleiben erhalten.
    func resetToDefaults() {
        settings = settings.resettingAppearance()
    }

    /// Verfügbare BLE-Profile inklusive eines gültigen eigenen Profils.
    var availableBLEProfiles: [BLEAdapterProfile] {
        BLEAdapterProfile.available(custom: settings.customBLEProfile)
    }

    func rememberConnection(_ target: ConnectionTarget) {
        var updated = settings
        updated.lastConnectionKind = target.kind
        switch target {
        case .bluetooth(let peripheralID, let name, let profile):
            updated.lastBLEPeripheralID = peripheralID
            updated.lastBLEPeripheralName = name
            updated.lastBLEProfileID = profile.id
        case .wifi(let host, let port):
            updated.wifiHost = host
            updated.wifiPort = port
        }
        settings = updated
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
