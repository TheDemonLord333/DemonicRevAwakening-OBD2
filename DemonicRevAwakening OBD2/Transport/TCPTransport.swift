//
//  TCPTransport.swift
//  DemonicRevAwakening OBD2
//
//  ELM327-Datenstrom über WLAN (TCP) mit dem Network-Framework.
//  Der Zugriff auf private Adressen löst unter iOS die Abfrage
//  „Lokales Netzwerk“ aus (NSLocalNetworkUsageDescription).
//

import Foundation
import Network

final class TCPTransport: OBDTransport {
    let displayName: String
    var onReceive: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    private let host: String
    private let port: Int
    private var connection: NWConnection?
    private let readiness = PendingOperation<Void>()
    private var lastWaitingReason: String?
    private var isClosed = false

    init(host: String, port: Int) {
        self.host = host.trimmingCharacters(in: .whitespaces)
        self.port = port
        self.displayName = "\(self.host):\(port)"
    }

    func open() async throws {
        guard WiFiEndpointValidator.isValidHost(host),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)),
              WiFiEndpointValidator.isValidPort(port) else {
            throw TransportError.invalidEndpoint
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = 8
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        // Der Adapter ist nur im lokalen WLAN erreichbar – nie über Mobilfunk.
        parameters.prohibitedInterfaceTypes = [.cellular]

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.handle(state)
            }
        }

        do {
            try await readiness.run(timeout: .seconds(12), timeoutError: self.timeoutError()) {
                connection.start(queue: .main)
            }
        } catch {
            connection.cancel()
            throw error
        }
        receiveNext()
    }

    private func timeoutError() -> TransportError {
        if let lastWaitingReason {
            return .networkWaiting(lastWaitingReason)
        }
        return .connectionTimeout
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            readiness.succeed(())
        case .waiting(let error):
            // Typisch: falsches WLAN, Adapter aus oder lokales Netzwerk (noch)
            // nicht erlaubt. Während des Verbindungsaufbaus weiter warten – der
            // Nutzer beantwortet ggf. gerade die Berechtigungsabfrage.
            lastWaitingReason = error.localizedDescription
            if !readiness.isPending {
                finish(with: TransportError.networkWaiting(error.localizedDescription))
            }
        case .failed(let error):
            if readiness.isPending {
                readiness.fail(TransportError.connectionFailed(error.localizedDescription))
            } else {
                finish(with: TransportError.disconnected(error.localizedDescription))
            }
        case .cancelled:
            readiness.fail(TransportError.disconnected(nil))
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    self.onReceive?(data)
                }
                if let error {
                    self.finish(with: TransportError.disconnected(error.localizedDescription))
                } else if isComplete {
                    self.finish(with: TransportError.disconnected("Der Adapter hat die Verbindung geschlossen."))
                } else {
                    self.receiveNext()
                }
            }
        }
    }

    func write(_ data: Data) async throws {
        guard !isClosed, let connection else { throw TransportError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: TransportError.writeFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func finish(with error: Error) {
        guard !isClosed else { return }
        isClosed = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        onClose?(error)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        readiness.fail(TransportError.disconnected(nil))
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        onReceive = nil
    }
}
