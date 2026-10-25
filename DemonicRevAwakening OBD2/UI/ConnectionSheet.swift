//
//  ConnectionSheet.swift
//  DemonicRevAwakening OBD2
//
//  Verbindungsaufbau: Bluetooth LE (nur dokumentierte bzw. manuell
//  konfigurierte Profile), WLAN/TCP oder Demo.
//

import SwiftUI

struct ConnectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case bluetooth = "Bluetooth LE"
        case wifi = "WLAN"
        case demo = "Demo"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .bluetooth

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Verbindungsart", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                switch tab {
                case .bluetooth:
                    BluetoothConnectView(onConnect: connect)
                case .wifi:
                    WiFiConnectView(onConnect: connect)
                case .demo:
                    DemoStartView {
                        model.connection.startDemo()
                        dismiss()
                    }
                }
            }
            .background(BackgroundGradient())
            .navigationTitle("Verbinden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .onAppear {
            if model.settings.settings.lastConnectionKind == .wifi { tab = .wifi }
        }
        .onDisappear {
            model.bluetooth.stopScan()
        }
    }

    private func connect(_ target: ConnectionTarget) {
        model.connect(to: target)
        dismiss()
    }
}

// MARK: - Bluetooth LE

private struct BluetoothConnectView: View {
    @Environment(AppModel.self) private var model
    var onConnect: (ConnectionTarget) -> Void

    @State private var selected: DiscoveredPeripheral?
    @State private var showUnnamed = false

    var body: some View {
        let bluetooth = model.bluetooth
        List {
            Section {
                Text("Es werden nur Adapter mit dokumentiertem oder von dir eingetragenem BLE-Profil unterstützt. Klassische Bluetooth-Adapter (SPP) funktionieren mit iOS-Apps in der Regel nicht.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if let message = bluetooth.availabilityMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                Button {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                } label: {
                    HStack {
                        Label(bluetooth.isScanning ? "Suche läuft – stoppen" : "Nach Adaptern suchen",
                              systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        if bluetooth.isScanning { ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                if let last = model.lastBluetoothTarget {
                    Button {
                        onConnect(last)
                    } label: {
                        Label("Zuletzt verwendet: \(last.displayName)", systemImage: "clock.arrow.circlepath")
                            .frame(minHeight: 44)
                    }
                }
            }

            let recognized = bluetooth.discovered.filter { $0.recognition != .unknown }
            let others = bluetooth.discovered.filter { $0.recognition == .unknown && (showUnnamed || $0.name != nil) }

            Section("Erkannte Adapter") {
                if recognized.isEmpty {
                    Text(bluetooth.isScanning ? "Suche …" : "Noch kein passender Adapter gefunden.")
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(recognized) { peripheral in
                    PeripheralRow(peripheral: peripheral) { selected = peripheral }
                }
            }

            Section {
                ForEach(others.sorted { $0.rssi > $1.rssi }) { peripheral in
                    PeripheralRow(peripheral: peripheral) { selected = peripheral }
                }
                Toggle("Unbenannte Geräte anzeigen", isOn: $showUnnamed)
            } header: {
                Text("Weitere Geräte – nicht konfiguriert")
            } footer: {
                Text("Diese Geräte wurden nicht als OBD2-Adapter erkannt. Ein beliebiges BLE-Gerät ist kein unterstützter Adapter.")
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { bluetooth.activate() }
        .sheet(item: $selected) { peripheral in
            ProfileChooser(peripheral: peripheral, onConnect: onConnect)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct PeripheralRow: View {
    let peripheral: DiscoveredPeripheral
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peripheral.displayName)
                        .foregroundStyle(Theme.textPrimary)
                    Text(recognitionText)
                        .font(.caption)
                        .foregroundStyle(color)
                }
                Spacer()
                Text("\(peripheral.rssi) dBm")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("\(peripheral.displayName), \(recognitionText)")
    }

    private var recognitionText: String {
        switch peripheral.recognition {
        case .advertisesProfileService: "Bewirbt den Dienst eines bekannten Profils"
        case .nameSuggestsProfile: "Name deutet auf ein bekanntes Profil hin – wird beim Verbinden geprüft"
        case .unknown: "Nicht konfiguriert / nicht unterstützt"
        }
    }

    private var icon: String {
        switch peripheral.recognition {
        case .advertisesProfileService: "checkmark.seal.fill"
        case .nameSuggestsProfile: "questionmark.diamond.fill"
        case .unknown: "circle.dashed"
        }
    }

    private var color: Color {
        switch peripheral.recognition {
        case .advertisesProfileService: Theme.green
        case .nameSuggestsProfile: Theme.blurple
        case .unknown: Theme.textTertiary
        }
    }
}

private struct ProfileChooser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let peripheral: DiscoveredPeripheral
    var onConnect: (ConnectionTarget) -> Void

    @State private var profileID: String = ""

    var body: some View {
        let profiles = model.settings.availableBLEProfiles
        NavigationStack {
            Form {
                Section {
                    Text(peripheral.displayName).font(.headline)
                    if peripheral.recognition == .unknown {
                        Label("Dieses Gerät wurde nicht als OBD2-Adapter erkannt. Verbinde nur, wenn du sicher bist, dass es sich um einen BLE-OBD2-Adapter mit dem gewählten Profil handelt. Beim Verbinden wird geprüft, ob Dienst und Characteristics vorhanden sind.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
                Section {
                    Picker("Adapterprofil", selection: $profileID) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    if let profile = profiles.first(where: { $0.id == profileID }) {
                        LabeledContent("Service", value: profile.serviceUUID)
                        LabeledContent("Notify", value: profile.notifyCharacteristicUUID)
                        LabeledContent("Write", value: profile.writeCharacteristicUUID)
                        Text("Quelle: \(profile.documentationSource)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                } footer: {
                    Text("Eigene Profile legst du in den Einstellungen unter „Erweitert“ an.")
                }
                Section {
                    Button {
                        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
                        dismiss()
                        onConnect(.bluetooth(peripheralID: peripheral.id,
                                             peripheralName: peripheral.displayName, profile: profile))
                    } label: {
                        Label("Mit diesem Profil verbinden", systemImage: "link")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!profiles.contains { $0.id == profileID })
                }
            }
            .navigationTitle("Adapterprofil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .onAppear {
            profileID = peripheral.recognition.suggestedProfileID
                ?? model.settings.settings.lastBLEProfileID
                ?? profiles.first?.id
                ?? ""
        }
    }
}

// MARK: - WLAN

private struct WiFiConnectView: View {
    @Environment(AppModel.self) private var model
    var onConnect: (ConnectionTarget) -> Void

    @State private var host = ""
    @State private var portText = ""

    var body: some View {
        let port = Int(portText) ?? -1
        let validation = WiFiEndpointValidator.validationMessage(host: host, port: port)
        Form {
            Section {
                TextField("IP-Adresse oder Hostname", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 44)
                TextField("Port", text: $portText)
                    .keyboardType(.numberPad)
                    .frame(minHeight: 44)
                if let validation {
                    Text(validation)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            } header: {
                Text("ELM327-kompatibler WLAN-Adapter")
            } footer: {
                Text("Verbinde das iPhone zuerst in den iOS-Einstellungen mit dem WLAN des Adapters. Viele Adapter nutzen 192.168.0.10, Port 35000 – maßgeblich ist die Anleitung deines Adapters. Beim ersten Verbinden fragt iOS nach dem Zugriff auf das lokale Netzwerk.")
            }
            Section {
                Button {
                    onConnect(.wifi(host: host.trimmingCharacters(in: .whitespaces), port: port))
                } label: {
                    Label("Verbinden", systemImage: "wifi")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(validation != nil)
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            host = model.settings.settings.wifiHost
            portText = String(model.settings.settings.wifiPort)
        }
    }
}

// MARK: - Demo

private struct DemoStartView: View {
    var onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoBadge()
                Text("Erlebe den Dämon ohne Adapter – auch im Simulator. Die Demo nutzt dieselbe Animationslogik wie echte Fahrzeugdaten: Motorstart, Leerlauf, Drehzahlanstieg und Beruhigung, oder du stellst die Drehzahl manuell ein.")
                    .foregroundStyle(Theme.textSecondary)
                Text("Eine aktive Live-Verbindung wird dabei getrennt. Demo-Daten ersetzen niemals automatisch eine unterbrochene Verbindung.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                Button(action: onStart) {
                    Label("Demo starten", systemImage: "play.fill")
                }
                .buttonStyle(DemonButtonStyle(kind: .primary))
            }
            .padding(20)
        }
    }
}
