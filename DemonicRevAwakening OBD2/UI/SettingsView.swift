//
//  SettingsView.swift
//  DemonicRevAwakening OBD2
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isResetConfirmationPresented = false

    var body: some View {
        @Bindable var store = model.settings
        let thresholds = store.settings.thresholds
        let gap = RPMThresholds.minimumGap

        NavigationStack {
            Form {
                Section {
                    thresholdStepper("Erwachend ab", value: $store.settings.thresholds.awakeningStart,
                                     range: RPMThresholds.lowestAwakeningStart...(thresholds.awakeStart - gap))
                    thresholdStepper("Wach ab", value: $store.settings.thresholds.awakeStart,
                                     range: (thresholds.awakeningStart + gap)...(thresholds.unleashedStart - gap))
                    thresholdStepper("Entfesselt ab", value: $store.settings.thresholds.unleashedStart,
                                     range: (thresholds.awakeStart + gap)...(thresholds.scaleMax - gap))
                    thresholdStepper("Skalenende", value: $store.settings.thresholds.scaleMax,
                                     range: max(RPMThresholds.scaleRange.lowerBound, thresholds.unleashedStart + gap)...RPMThresholds.scaleRange.upperBound)
                    ForEach(thresholds.validationIssues, id: \.self) { issue in
                        Text(issue).font(.footnote).foregroundStyle(Theme.warning)
                    }
                } header: {
                    Text("Drehzahlschwellen")
                } footer: {
                    Text("Unterhalb von „Erwachend ab“ schläft der Dämon im Leerlauf. Das sind reine Animationsschwellen – keine empfohlenen Drehzahlen und keine Motorschutzgrenzen.")
                }

                Section {
                    percentSlider("Animationsintensität", value: $store.settings.animationIntensity,
                                  range: AppSettings.intensityRange)
                    percentSlider("Augenleuchten", value: $store.settings.eyeGlowStrength, range: AppSettings.unitRange)
                    percentSlider("Partikel", value: $store.settings.particleStrength, range: AppSettings.unitRange)
                    Toggle("Reduzierte Effekte", isOn: $store.settings.reducedEffects)
                        .frame(minHeight: 44)
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text("Die iOS-Einstellung „Bewegung reduzieren“ wird automatisch berücksichtigt. Es gibt keine Blitz- oder Stroboskopeffekte.")
                }

                Section {
                    Toggle("Display eingeschaltet lassen", isOn: $store.settings.keepScreenOn)
                        .frame(minHeight: 44)
                    Toggle("Automatisch neu verbinden", isOn: $store.settings.autoReconnect)
                        .frame(minHeight: 44)
                } header: {
                    Text("Sitzung")
                } footer: {
                    Text("Das Display bleibt nur während einer aktiven Live- oder Demo-Sitzung an. Die Wiederverbindung versucht es mit wachsenden Abständen höchstens sechsmal und lässt sich jederzeit abbrechen.")
                }

                Section("WLAN-Adapter") {
                    TextField("IP-Adresse", text: $store.settings.wifiHost)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $store.settings.wifiPort, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    if let message = WiFiEndpointValidator.validationMessage(host: store.settings.wifiHost,
                                                                             port: store.settings.wifiPort) {
                        Text(message).font(.footnote).foregroundStyle(Theme.warning)
                    }
                }

                Section {
                    ForEach(BLEAdapterProfile.builtIn) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).font(.headline)
                            Text("Service \(profile.serviceUUID) · Notify \(profile.notifyCharacteristicUUID) · Write \(profile.writeCharacteristicUUID)")
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                            Text("Quelle: \(profile.documentationSource)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Mitgelieferte BLE-Profile")
                } footer: {
                    Text("Mitgeliefert sind nur Profile mit veröffentlichter Herstellerdokumentation. Kompatibilität ist erst nach einem Test mit deinem Adapter und Fahrzeug bestätigt.")
                }

                Section {
                    TextField("Name", text: $store.settings.customBLEProfile.name)
                    uuidField("Service-UUID", text: $store.settings.customBLEProfile.serviceUUID)
                    uuidField("Notify-Characteristic", text: $store.settings.customBLEProfile.notifyCharacteristicUUID)
                    uuidField("Write-Characteristic", text: $store.settings.customBLEProfile.writeCharacteristicUUID)
                    Picker("Schreibmodus", selection: $store.settings.customBLEProfile.writePreference) {
                        ForEach(BLEAdapterProfile.WritePreference.allCases, id: \.self) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    let issues = store.settings.customBLEProfile.validationIssues
                    if issues.isEmpty {
                        Label("Profil ist vollständig und beim Verbinden auswählbar.", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.green)
                    } else {
                        ForEach(issues, id: \.self) { issue in
                            Text(issue).font(.footnote).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Button("Eigenes Profil leeren", role: .destructive) {
                        store.settings.customBLEProfile = .customTemplate
                    }
                } header: {
                    Text("Erweitert: Eigenes BLE-Profil")
                } footer: {
                    Text("Nur für Adapter, deren UUIDs du aus der Herstellerdokumentation oder per BLE-Scanner-App (z. B. nRF Connect) kennst. Erlaubt sind 16-Bit (FFF0), 32-Bit oder 128-Bit-UUIDs. Beim Verbinden prüft die App Dienst, Characteristics, Benachrichtigungen und Schreibmodus.")
                }

                Section {
                    Button("Standardwerte wiederherstellen", role: .destructive) {
                        isResetConfirmationPresented = true
                    }
                    .frame(minHeight: 44)
                } footer: {
                    Text("Setzt Schwellen und Darstellung zurück. Verbindungsdaten und dein eigenes Profil bleiben erhalten.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(BackgroundGradient())
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Standardwerte wiederherstellen?", isPresented: $isResetConfirmationPresented,
                                titleVisibility: .visible) {
                Button("Zurücksetzen", role: .destructive) { store.resetToDefaults() }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    private func thresholdStepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let safeRange = range.lowerBound <= range.upperBound ? range : range.lowerBound...range.lowerBound
        return Stepper(value: value, in: safeRange, step: 100) {
            HStack {
                Text(title)
                Spacer()
                Text("\(RPMReadout.rpmText(value.wrappedValue, freshness: .fresh)) RPM")
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityValue("\(Int(value.wrappedValue)) RPM")
    }

    private func percentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded())) %")
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(Theme.green)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 4)
    }

    private func uuidField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.body.monospaced())
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }
}
