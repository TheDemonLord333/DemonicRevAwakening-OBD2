//
//  SettingsAndDemoTests.swift
//  DemonicRevAwakening OBD2Tests
//

import Foundation
import Testing
@testable import DemonicRevAwakening_OBD2

struct ThresholdTests {
    @Test func defaultsAreValid() {
        #expect(RPMThresholds.standard.isValid)
        #expect(RPMThresholds.standard.normalized() == .standard)
    }

    @Test func detectsWrongOrder() {
        var thresholds = RPMThresholds.standard
        thresholds.awakeStart = 900
        #expect(!thresholds.isValid)
        #expect(thresholds.validationIssues.contains { $0.contains("Wach ab") })
    }

    @Test func normalizationRestoresOrder() {
        let broken = RPMThresholds(awakeningStart: 3_000, awakeStart: 1_000, unleashedStart: 500, scaleMax: 20_000)
        let fixed = broken.normalized()
        #expect(fixed.isValid)
        #expect(fixed.awakeningStart < fixed.awakeStart)
        #expect(fixed.awakeStart < fixed.unleashedStart)
        #expect(fixed.unleashedStart < fixed.scaleMax)
        #expect(fixed.scaleMax == RPMThresholds.scaleRange.upperBound)
    }
}

struct AppSettingsTests {
    @Test func decodingToleratesMissingKeys() throws {
        let json = Data(#"{"keepScreenOn": false, "wifiPort": 23}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.keepScreenOn == false)
        #expect(settings.wifiPort == 23)
        #expect(settings.thresholds == .standard)
        #expect(settings.wifiHost == "192.168.0.10")
    }

    @Test func roundTrip() throws {
        var settings = AppSettings.standard
        settings.eyeGlowStrength = 0.4
        settings.lastBLEPeripheralID = UUID()
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test func resetKeepsConnectionData() {
        var settings = AppSettings.standard
        settings.wifiHost = "192.168.4.1"
        settings.particleStrength = 0.1
        settings.thresholds.unleashedStart = 5_000
        let reset = settings.resettingAppearance()
        #expect(reset.wifiHost == "192.168.4.1")
        #expect(reset.particleStrength == AppSettings.standard.particleStrength)
        #expect(reset.thresholds == .standard)
    }

    @Test func sanitizeClampsValues() {
        var settings = AppSettings.standard
        settings.animationIntensity = 5
        settings.eyeGlowStrength = -1
        settings.wifiPort = 0
        let clean = settings.sanitized()
        #expect(clean.animationIntensity == 1)
        #expect(clean.eyeGlowStrength == 0)
        #expect(clean.wifiPort == 35_000)
    }

    @Test @MainActor func storePersistsAndResets() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.settings.keepScreenOn = false
        store.settings.wifiHost = "10.0.0.5"
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings.keepScreenOn == false)
        #expect(reloaded.settings.wifiHost == "10.0.0.5")

        reloaded.resetToDefaults()
        #expect(reloaded.settings.keepScreenOn == true)
        #expect(reloaded.settings.wifiHost == "10.0.0.5")

        // Ungültige Werte werden beim Setzen korrigiert und so gespeichert.
        reloaded.settings.eyeGlowStrength = 5
        reloaded.settings.thresholds.awakeStart = 100
        #expect(reloaded.settings.eyeGlowStrength == 1)
        #expect(reloaded.settings.thresholds.isValid)
        #expect(SettingsStore(defaults: defaults).settings == reloaded.settings)
    }
}

struct ValidatorTests {
    @Test(arguments: ["FFF0", "fff1", "0000FFF0", "0000FFF0-0000-1000-8000-00805F9B34FB"])
    func validUUIDs(_ value: String) {
        #expect(BLEUUIDValidator.isValid(value))
    }

    @Test(arguments: ["", "FFF", "XYZ0", "0000FFF0-0000-1000-8000", "not-a-uuid"])
    func invalidUUIDs(_ value: String) {
        #expect(!BLEUUIDValidator.isValid(value))
    }

    @Test func shortAndLongFormMatch() {
        #expect(BLEAdapterProfile.obdLinkCX.matchesAdvertisedService("0000FFF0-0000-1000-8000-00805F9B34FB"))
        #expect(BLEAdapterProfile.obdLinkCX.matchesAdvertisedService("fff0"))
        #expect(!BLEAdapterProfile.obdLinkCX.matchesAdvertisedService("FFE0"))
    }

    @Test func profiles() {
        #expect(BLEAdapterProfile.obdLinkCX.isValid)
        #expect(!BLEAdapterProfile.customTemplate.isValid)
        #expect(BLEAdapterProfile.available(custom: .customTemplate) == BLEAdapterProfile.builtIn)
        #expect(BLEAdapterProfile.obdLinkCX.nameSuggestsProfile("OBDLink CX 1234"))
        #expect(!BLEAdapterProfile.obdLinkCX.nameSuggestsProfile("JBL Flip"))
    }

    @Test func wifiEndpoint() {
        #expect(WiFiEndpointValidator.isValidHost("192.168.0.10"))
        #expect(WiFiEndpointValidator.isValidHost("obd.local"))
        #expect(!WiFiEndpointValidator.isValidHost("192.168.0.300"))
        #expect(!WiFiEndpointValidator.isValidHost("192 168"))
        #expect(!WiFiEndpointValidator.isValidHost(""))
        #expect(WiFiEndpointValidator.isValidPort(35_000))
        #expect(!WiFiEndpointValidator.isValidPort(70_000))
    }
}

struct DemoEngineTests {
    @Test func scenarioCoversAllStates() {
        var brain = DemonBrain()
        var engine = DemoEngine()
        engine.restart()
        var moods = Set<DemonMood>()
        let dt = 1.0 / 30
        for _ in 0..<Int(DemoEngine.scenarioDuration / dt) {
            engine.advance(by: dt)
            moods.insert(brain.update(input: .rpm(engine.rpm), deltaTime: dt).mood)
        }
        #expect(moods.isSuperset(of: [.engineOff, .idle, .awakening, .awake, .unleashed]))
    }

    @Test func scenarioStaysInRange() {
        for step in 0..<440 {
            let rpm = DemoEngine.scenarioRPM(at: Double(step) / 10)
            #expect(DemoEngine.rpmRange.contains(rpm))
        }
    }

    @Test func manualModeFollowsSliderAndClamps() {
        var engine = DemoEngine()
        engine.setMode(.manual)
        engine.manualTargetRPM = 9_999
        #expect(engine.manualTargetRPM == 8_000)
        engine.manualTargetRPM = 3_000
        for _ in 0..<120 { engine.advance(by: 1.0 / 30) }
        #expect(abs(engine.rpm - 3_000) < 1)
    }

    @Test func pauseHoldsValue() {
        var engine = DemoEngine()
        engine.restart()
        for _ in 0..<300 { engine.advance(by: 1.0 / 30) }
        let held = engine.rpm
        let time = engine.scenarioTime
        engine.pause()
        for _ in 0..<60 { engine.advance(by: 1.0 / 30) }
        #expect(engine.rpm == held)
        #expect(engine.scenarioTime == time)
        engine.restart()
        #expect(engine.scenarioTime == 0)
        #expect(!engine.isPaused)
    }
}
