//
//  BluetoothCentral.swift
//  DemonicRevAwakening OBD2
//
//  Gerätesuche und Verbindungsaufbau über CoreBluetooth. Die Suche zeigt
//  alle BLE-Geräte, unterscheidet aber klar zwischen „Profil-Dienst wird
//  beworben“, „Name deutet auf ein Profil hin“ und „unbekannt“. Ob ein
//  Gerät tatsächlich unterstützt wird, zeigt erst die GATT-Prüfung beim
//  Verbinden (siehe `BLETransport`).
//

import CoreBluetooth
import Foundation
import Observation

/// Einordnung eines gefundenen Geräts.
nonisolated enum AdapterRecognition: Equatable, Sendable {
    /// Das Gerät bewirbt den Dienst eines bekannten Profils.
    case advertisesProfileService(profileID: String)
    /// Nur der Gerätename deutet auf ein Profil hin.
    case nameSuggestsProfile(profileID: String)
    /// Nicht als OBD2-Adapter erkannt / nicht konfiguriert.
    case unknown

    var suggestedProfileID: String? {
        switch self {
        case .advertisesProfileService(let id), .nameSuggestsProfile(let id): id
        case .unknown: nil
        }
    }
}

nonisolated struct DiscoveredPeripheral: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String?
    var rssi: Int
    var advertisedServices: [String]
    var recognition: AdapterRecognition
    var lastSeen: Date

    var displayName: String { name ?? "Unbenanntes Gerät" }
}

@Observable
final class BluetoothCentral: NSObject {
    private(set) var state: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var discovered: [DiscoveredPeripheral] = []

    /// Liefert die aktuell verfügbaren Profile (mitgeliefert + eigenes).
    @ObservationIgnored var profilesProvider: () -> [BLEAdapterProfile] = { BLEAdapterProfile.builtIn }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var scanRequested = false
    @ObservationIgnored private var scanStopTask: Task<Void, Never>?
    @ObservationIgnored private var poweredOnWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var pendingConnections: [UUID: PendingOperation<CBPeripheral>] = [:]
    @ObservationIgnored private var disconnectHandlers: [UUID: (Error?) -> Void] = [:]

    /// Aktuelle Berechtigung (ohne den Dialog auszulösen).
    var authorization: CBManagerAuthorization { CBManager.authorization }

    /// Erzeugt den CBCentralManager erst bei Bedarf, damit der
    /// Bluetooth-Berechtigungsdialog nicht schon beim App-Start erscheint.
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    /// Verständlicher Hinweis, falls Bluetooth nicht nutzbar ist.
    var availabilityMessage: String? {
        if authorization == .denied || authorization == .restricted {
            return "Bluetooth-Zugriff ist nicht erlaubt. Erlaube ihn in den iOS-Einstellungen unter Datenschutz & Sicherheit › Bluetooth."
        }
        switch state {
        case .poweredOn, .unknown, .resetting:
            return nil
        case .poweredOff:
            return "Bluetooth ist ausgeschaltet. Schalte es im Kontrollzentrum oder in den Einstellungen ein."
        case .unauthorized:
            return "Bluetooth-Zugriff ist nicht erlaubt. Erlaube ihn in den iOS-Einstellungen."
        case .unsupported:
            return "Bluetooth LE ist auf diesem Gerät nicht verfügbar (z. B. im Simulator). Nutze WLAN oder den Demo-Modus."
        @unknown default:
            return "Bluetooth ist derzeit nicht verfügbar."
        }
    }

    // MARK: - Suche

    func startScan(duration: TimeInterval = 15) {
        activate()
        scanRequested = true
        discovered.removeAll()
        guard state == .poweredOn, let central else { return }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        scanStopTask?.cancel()
        scanStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        scanRequested = false
        scanStopTask?.cancel()
        scanStopTask = nil
        if isScanning { central?.stopScan() }
        isScanning = false
    }

    // MARK: - Verbindung

    /// Verbindet mit dem Gerät; wirft bei Zeitüberschreitung oder Fehler.
    func connect(peripheralID: UUID, onDisconnect: @escaping (Error?) -> Void) async throws -> CBPeripheral {
        activate()
        try await waitUntilPoweredOn()
        guard let central else { throw TransportError.bluetoothUnavailable("Bluetooth ist nicht verfügbar.") }

        let peripheral = peripherals[peripheralID]
            ?? central.retrievePeripherals(withIdentifiers: [peripheralID]).first
        guard let peripheral else { throw TransportError.deviceNotFound }
        peripherals[peripheralID] = peripheral

        if peripheral.state == .connected {
            disconnectHandlers[peripheralID] = onDisconnect
            return peripheral
        }

        let operation = PendingOperation<CBPeripheral>()
        pendingConnections[peripheralID] = operation
        defer { pendingConnections[peripheralID] = nil }
        do {
            let connected = try await operation.run(timeout: .seconds(12),
                                                    timeoutError: TransportError.connectionTimeout) {
                central.connect(peripheral, options: nil)
            }
            disconnectHandlers[peripheralID] = onDisconnect
            return connected
        } catch {
            central.cancelPeripheralConnection(peripheral)
            throw error
        }
    }

    func cancelConnection(_ peripheral: CBPeripheral) {
        disconnectHandlers[peripheral.identifier] = nil
        pendingConnections[peripheral.identifier]?.fail(CancellationError())
        central?.cancelPeripheralConnection(peripheral)
    }

    private func waitUntilPoweredOn() async throws {
        if state == .unknown || state == .resetting {
            // Der erste Zustand kommt asynchron; kurz darauf warten.
            let waiter = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.releasePoweredOnWaiters()
            }
            await withCheckedContinuation { continuation in
                poweredOnWaiters.append(continuation)
            }
            waiter.cancel()
        }
        guard state == .poweredOn else {
            throw TransportError.bluetoothUnavailable(availabilityMessage ?? "Bluetooth ist nicht eingeschaltet.")
        }
    }

    private func releasePoweredOnWaiters() {
        let waiters = poweredOnWaiters
        poweredOnWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    // MARK: - Ereignisse (auf dem Main-Thread, da `queue: nil`)

    fileprivate func handleStateUpdate(_ newState: CBManagerState) {
        state = newState
        if newState != .unknown, newState != .resetting {
            releasePoweredOnWaiters()
        }
        if newState == .poweredOn {
            if scanRequested { startScan() }
        } else {
            isScanning = false
            let error = TransportError.bluetoothUnavailable(availabilityMessage ?? "Bluetooth ist nicht verfügbar.")
            pendingConnections.values.forEach { $0.fail(error) }
            let handlers = disconnectHandlers
            disconnectHandlers.removeAll()
            handlers.values.forEach { $0(error) }
        }
    }

    fileprivate func handleDiscovery(_ peripheral: CBPeripheral, name: String?, services: [String], rssi: Int) {
        peripherals[peripheral.identifier] = peripheral
        let profiles = profilesProvider()
        let recognition: AdapterRecognition
        if let profile = profiles.first(where: { profile in services.contains { profile.matchesAdvertisedService($0) } }) {
            recognition = .advertisesProfileService(profileID: profile.id)
        } else if let profile = profiles.first(where: { $0.nameSuggestsProfile(name) }) {
            recognition = .nameSuggestsProfile(profileID: profile.id)
        } else {
            recognition = .unknown
        }
        let entry = DiscoveredPeripheral(id: peripheral.identifier, name: name, rssi: rssi,
                                         advertisedServices: services, recognition: recognition,
                                         lastSeen: Date())
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[index] = entry
        } else {
            discovered.append(entry)
        }
    }

    fileprivate func handleConnected(_ peripheral: CBPeripheral) {
        pendingConnections[peripheral.identifier]?.succeed(peripheral)
    }

    fileprivate func handleConnectionFailure(_ peripheral: CBPeripheral, error: Error?) {
        let reason = error?.localizedDescription ?? "Unbekannter Fehler"
        pendingConnections[peripheral.identifier]?.fail(TransportError.connectionFailed(reason))
    }

    fileprivate func handleDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        pendingConnections[peripheral.identifier]?.fail(TransportError.disconnected(error?.localizedDescription))
        if let handler = disconnectHandlers.removeValue(forKey: peripheral.identifier) {
            handler(error.map { TransportError.disconnected($0.localizedDescription) })
        }
    }
}

extension BluetoothCentral: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = central.state
        MainActor.assumeIsolated {
            handleStateUpdate(newState)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? localName
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            handleDiscovery(peripheral, name: name, services: services, rssi: rssi)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            handleConnected(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            handleConnectionFailure(peripheral, error: error)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            handleDisconnect(peripheral, error: error)
        }
    }
}
