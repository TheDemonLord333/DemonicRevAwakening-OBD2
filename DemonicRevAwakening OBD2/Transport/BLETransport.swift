//
//  BLETransport.swift
//  DemonicRevAwakening OBD2
//
//  ELM327-Datenstrom über ein dokumentiertes BLE-Adapterprofil:
//  Dienst und Characteristics werden per GATT-Discovery geprüft,
//  Benachrichtigungen aktiviert, Schreibmodus und Paketgröße gemäß
//  Profil und tatsächlichen Characteristic-Eigenschaften gewählt.
//

import CoreBluetooth
import Foundation

final class BLETransport: NSObject, OBDTransport {
    let displayName: String
    var onReceive: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    private let central: BluetoothCentral
    private let peripheralID: UUID
    private let profile: BLEAdapterProfile

    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var isClosed = false

    private let serviceDiscovery = PendingOperation<Void>()
    private let characteristicDiscovery = PendingOperation<Void>()
    private let notificationSetup = PendingOperation<Void>()
    private let writeAcknowledgement = PendingOperation<Void>()
    private var readyToSendWaiters: [CheckedContinuation<Void, Never>] = []

    init(central: BluetoothCentral, peripheralID: UUID, peripheralName: String, profile: BLEAdapterProfile) {
        self.central = central
        self.peripheralID = peripheralID
        self.profile = profile
        self.displayName = peripheralName
        super.init()
    }

    func open() async throws {
        guard profile.isValid else {
            throw TransportError.characteristicNotUsable("Das BLE-Profil „\(profile.name)“ ist unvollständig.")
        }
        let serviceUUID = CBUUID(string: profile.serviceUUID)
        let notifyUUID = CBUUID(string: profile.notifyCharacteristicUUID)
        let writeUUID = CBUUID(string: profile.writeCharacteristicUUID)

        let peripheral = try await central.connect(peripheralID: peripheralID) { [weak self] error in
            self?.handleDisconnect(error)
        }
        self.peripheral = peripheral
        peripheral.delegate = self

        // 1. Dienst des Profils suchen.
        try await serviceDiscovery.run(timeout: .seconds(10), timeoutError: TransportError.connectionTimeout) {
            peripheral.discoverServices([serviceUUID])
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            throw TransportError.serviceNotFound(profile: profile.name)
        }

        // 2. Characteristics suchen und Eigenschaften prüfen.
        try await characteristicDiscovery.run(timeout: .seconds(10), timeoutError: TransportError.connectionTimeout) {
            peripheral.discoverCharacteristics([notifyUUID, writeUUID], for: service)
        }
        let characteristics = service.characteristics ?? []
        guard let notify = characteristics.first(where: { $0.uuid == notifyUUID }) else {
            throw TransportError.characteristicNotFound(profile.notifyCharacteristicUUID)
        }
        guard let write = characteristics.first(where: { $0.uuid == writeUUID }) else {
            throw TransportError.characteristicNotFound(profile.writeCharacteristicUUID)
        }
        guard notify.properties.contains(.notify) || notify.properties.contains(.indicate) else {
            throw TransportError.characteristicNotUsable(
                "Characteristic \(profile.notifyCharacteristicUUID) unterstützt keine Benachrichtigungen.")
        }
        writeType = try Self.resolveWriteType(preference: profile.writePreference, properties: write.properties,
                                              uuid: profile.writeCharacteristicUUID)
        notifyCharacteristic = notify
        writeCharacteristic = write

        // 3. Benachrichtigungen aktivieren.
        try await notificationSetup.run(timeout: .seconds(8), timeoutError: TransportError.connectionTimeout) {
            peripheral.setNotifyValue(true, for: notify)
        }
    }

    static func resolveWriteType(preference: BLEAdapterProfile.WritePreference,
                                 properties: CBCharacteristicProperties,
                                 uuid: String) throws -> CBCharacteristicWriteType {
        let withResponse = properties.contains(.write)
        let withoutResponse = properties.contains(.writeWithoutResponse)
        switch preference {
        case .automatic:
            if withoutResponse { return .withoutResponse }
            if withResponse { return .withResponse }
        case .withResponse:
            if withResponse { return .withResponse }
        case .withoutResponse:
            if withoutResponse { return .withoutResponse }
        }
        throw TransportError.characteristicNotUsable(
            "Characteristic \(uuid) erlaubt den gewählten Schreibmodus nicht.")
    }

    func write(_ data: Data) async throws {
        guard !isClosed, let peripheral, let characteristic = writeCharacteristic,
              peripheral.state == .connected else {
            throw TransportError.notConnected
        }
        // Paketgröße laut iOS für den gewählten Schreibmodus (MTU-abhängig).
        let chunkSize = max(20, peripheral.maximumWriteValueLength(for: writeType))
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            switch writeType {
            case .withoutResponse:
                // Flusskontrolle: nur senden, wenn CoreBluetooth Platz hat.
                while !peripheral.canSendWriteWithoutResponse {
                    await withCheckedContinuation { readyToSendWaiters.append($0) }
                    guard !isClosed else { throw TransportError.notConnected }
                }
                peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            default:
                try await writeAcknowledgement.run(timeout: .seconds(4),
                                                   timeoutError: TransportError.writeFailed("Keine Bestätigung")) {
                    peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
                }
            }
            offset = end
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        let error = TransportError.disconnected(nil)
        serviceDiscovery.fail(error)
        characteristicDiscovery.fail(error)
        notificationSetup.fail(error)
        writeAcknowledgement.fail(error)
        releaseReadyWaiters()
        if let peripheral {
            if peripheral.state == .connected, let notify = notifyCharacteristic {
                peripheral.setNotifyValue(false, for: notify)
            }
            central.cancelConnection(peripheral)
        }
        onReceive = nil
    }

    private func handleDisconnect(_ error: Error?) {
        guard !isClosed else { return }
        isClosed = true
        let failure = error ?? TransportError.disconnected(nil)
        serviceDiscovery.fail(failure)
        characteristicDiscovery.fail(failure)
        notificationSetup.fail(failure)
        writeAcknowledgement.fail(failure)
        releaseReadyWaiters()
        onClose?(failure)
    }

    private func releaseReadyWaiters() {
        let waiters = readyToSendWaiters
        readyToSendWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    // MARK: - Delegate-Ereignisse

    fileprivate func didDiscoverServices(error: Error?) {
        if let error {
            serviceDiscovery.fail(TransportError.connectionFailed(error.localizedDescription))
        } else {
            serviceDiscovery.succeed(())
        }
    }

    fileprivate func didDiscoverCharacteristics(error: Error?) {
        if let error {
            characteristicDiscovery.fail(TransportError.connectionFailed(error.localizedDescription))
        } else {
            characteristicDiscovery.succeed(())
        }
    }

    fileprivate func didUpdateNotificationState(uuid: CBUUID, isNotifying: Bool, error: Error?) {
        guard uuid == notifyCharacteristic?.uuid else { return }
        if let error {
            notificationSetup.fail(TransportError.notificationsFailed(error.localizedDescription))
        } else if isNotifying {
            notificationSetup.succeed(())
        }
    }

    fileprivate func didReceive(uuid: CBUUID, value: Data?) {
        guard uuid == notifyCharacteristic?.uuid, let value, !value.isEmpty else { return }
        onReceive?(value)
    }

    fileprivate func didWrite(error: Error?) {
        if let error {
            writeAcknowledgement.fail(TransportError.writeFailed(error.localizedDescription))
        } else {
            writeAcknowledgement.succeed(())
        }
    }

    fileprivate func readyToSend() {
        releaseReadyWaiters()
    }
}

extension BLETransport: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { didDiscoverServices(error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated { didDiscoverCharacteristics(error: error) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid
        let isNotifying = characteristic.isNotifying
        MainActor.assumeIsolated {
            didUpdateNotificationState(uuid: uuid, isNotifying: isNotifying, error: error)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let uuid = characteristic.uuid
        let value = characteristic.value
        MainActor.assumeIsolated { didReceive(uuid: uuid, value: value) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated { didWrite(error: error) }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        MainActor.assumeIsolated { readyToSend() }
    }
}
