//
//  AppModel.swift
//  DemonicRevAwakening OBD2
//
//  Verbindet Einstellungen, Datenquelle, Bluetooth und die Dämonen-Szene.
//

import Foundation
import Observation
import SpriteKit
import UIKit

/// Vom Renderer gemeldeter Zustand des Dämons (ca. 30 Hz). Eigenes Objekt,
/// damit nur die Ansichten neu zeichnen, die diese Werte tatsächlich lesen.
@Observable
final class DemonPresentation {
    var frame = DemonFrame.resting
    /// Nur bei Zustandswechseln aktualisiert – für Ansichten, die keine 30 Hz brauchen.
    var mood = DemonFrame.resting.mood
}

@Observable
final class AppModel {
    let settings: SettingsStore
    let bluetooth: BluetoothCentral
    let connection: VehicleConnectionController
    let presentation = DemonPresentation()
    @ObservationIgnored let demonScene: DemonScene

    @ObservationIgnored private var originalIdleTimerDisabled: Bool?
    @ObservationIgnored private var reduceMotion = false

    init(settings: SettingsStore = SettingsStore()) {
        let bluetooth = BluetoothCentral()
        let connection = VehicleConnectionController { target -> OBDTransport in
            switch target {
            case .bluetooth(let peripheralID, let name, let profile):
                return BLETransport(central: bluetooth, peripheralID: peripheralID,
                                    peripheralName: name, profile: profile)
            case .wifi(let host, let port):
                return TCPTransport(host: host, port: port)
            }
        }
        let scene = DemonScene(size: CGSize(width: 390, height: 520))

        self.settings = settings
        self.bluetooth = bluetooth
        self.connection = connection
        self.demonScene = scene

        bluetooth.profilesProvider = { [weak settings] in
            settings?.availableBLEProfiles ?? BLEAdapterProfile.builtIn
        }
        scene.inputProvider = { [weak connection] in
            connection?.demonInput() ?? .noConnection
        }
        let presentation = self.presentation
        var lastPublished: TimeInterval = 0
        scene.onFrame = { [weak presentation] frame in
            // Auf ca. 30 Hz begrenzen; Zustandswechsel immer sofort.
            let now = ProcessInfo.processInfo.systemUptime
            guard let presentation else { return }
            if frame.mood != presentation.mood {
                presentation.mood = frame.mood
            }
            if frame.mood != presentation.frame.mood || now - lastPublished >= 1.0 / 30 {
                lastPublished = now
                presentation.frame = frame
            }
        }
        applySettings()
    }

    // MARK: - Einstellungen

    func applySettings() {
        let current = settings.settings
        connection.autoReconnect = current.autoReconnect
        demonScene.thresholds = current.thresholds
        demonScene.renderSettings = DemonRenderSettings(
            animationIntensity: current.animationIntensity,
            eyeGlowStrength: current.eyeGlowStrength,
            particleStrength: current.particleStrength,
            reducedEffects: current.reducedEffects,
            reduceMotion: reduceMotion)
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        applySettings()
    }

    // MARK: - Verbindung

    func connect(to target: ConnectionTarget) {
        bluetooth.stopScan()
        settings.rememberConnection(target)
        connection.connect(to: target)
    }

    /// Zuletzt verwendetes BLE-Ziel, sofern Gerät und Profil bekannt sind.
    var lastBluetoothTarget: ConnectionTarget? {
        let current = settings.settings
        guard let id = current.lastBLEPeripheralID,
              let profile = settings.availableBLEProfiles.first(where: { $0.id == current.lastBLEProfileID }) else {
            return nil
        }
        return .bluetooth(peripheralID: id, peripheralName: current.lastBLEPeripheralName ?? profile.name,
                          profile: profile)
    }

    // MARK: - Lebenszyklus

    func sceneBecameActive() {
        connection.enterForeground()
    }

    func sceneEnteredBackground() {
        bluetooth.stopScan()
        connection.enterBackground()
        updateIdleTimer(isActive: false)
    }

    /// Hält das Display während einer aktiven Sitzung an (optional) und stellt
    /// den ursprünglichen Zustand danach wieder her.
    func updateIdleTimer(isActive: Bool) {
        let shouldKeepAwake = isActive && settings.settings.keepScreenOn && connection.isSessionActive
        let application = UIApplication.shared
        if shouldKeepAwake {
            if originalIdleTimerDisabled == nil {
                originalIdleTimerDisabled = application.isIdleTimerDisabled
            }
            application.isIdleTimerDisabled = true
        } else if let original = originalIdleTimerDisabled {
            application.isIdleTimerDisabled = original
            originalIdleTimerDisabled = nil
        }
    }
}
