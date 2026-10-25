//
//  MockELMTransport.swift
//  DemonicRevAwakening OBD2Tests
//
//  Simulierter ELM327-Adapter für Tests der OBD-Schicht.
//

import Foundation
@testable import DemonicRevAwakening_OBD2

@MainActor
final class MockELMTransport: OBDTransport {
    enum Reply {
        /// Antwort in `chunks` Fragmenten, optional verzögert.
        case respond(String, chunks: Int = 1, delay: Duration = .zero)
        /// Keine Antwort (Zeitüberschreitung).
        case silent
    }

    var displayName = "Mock-ELM327"
    var onReceive: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?

    var openError: Error?
    var handler: (String) -> Reply = MockELMTransport.healthyCar(rpmHex: "1A F8")
    private(set) var writtenCommands: [String] = []
    private(set) var isClosed = false
    private(set) var overlappingRequestDetected = false
    private var outstandingReplies = 0

    func open() async throws {
        if let openError { throw openError }
    }

    func write(_ data: Data) async throws {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if outstandingReplies > 0 { overlappingRequestDetected = true }
        writtenCommands.append(text)
        switch handler(text) {
        case .silent:
            break
        case .respond(let raw, let chunks, let delay):
            outstandingReplies += 1
            Task { @MainActor in
                if delay > .zero { try? await Task.sleep(for: delay) }
                self.outstandingReplies -= 1
                for piece in Self.split(raw, into: chunks) {
                    self.onReceive?(Data(piece.utf8))
                    await Task.yield()
                }
            }
        }
    }

    func close() {
        isClosed = true
    }

    /// Simuliert einen unerwarteten Verbindungsabbruch.
    func simulateDisconnect() {
        onClose?(TransportError.disconnected("Test"))
    }

    /// Spielt Daten unaufgefordert ein (z. B. verspätete Antworten).
    func inject(_ raw: String) {
        onReceive?(Data(raw.utf8))
    }

    static func split(_ raw: String, into chunks: Int) -> [String] {
        guard chunks > 1, raw.count > 1 else { return [raw] }
        let size = max(1, raw.count / chunks)
        var pieces: [String] = []
        var current = raw.startIndex
        while current < raw.endIndex {
            let next = raw.index(current, offsetBy: size, limitedBy: raw.endIndex) ?? raw.endIndex
            pieces.append(String(raw[current..<next]))
            current = next
        }
        return pieces
    }

    /// Typisches Fahrzeug (CAN 11 Bit, Header an) mit ELM327 v1.5.
    static func healthyCar(rpmHex: String, chunks: Int = 1, supportedMask: String = "BE 1F A8 13") -> (String) -> Reply {
        { command in
            switch command {
            case "ATZ": return .respond("\r\rELM327 v1.5\r\r>", chunks: chunks)
            case "ATI": return .respond("ELM327 v1.5\r\r>", chunks: chunks)
            case "ATDP": return .respond("AUTO, ISO 15765-4 (CAN 11/500)\r\r>", chunks: chunks)
            case "0100": return .respond("SEARCHING...\r7E8 06 41 00 \(supportedMask)\r\r>", chunks: chunks)
            case "010C": return .respond("7E8 04 41 0C \(rpmHex) AA AA AA\r\r>", chunks: chunks)
            case "010D": return .respond("7E8 03 41 0D 32 AA AA AA AA\r\r>", chunks: chunks)
            case "0104": return .respond("7E8 03 41 04 80 AA AA AA AA\r\r>", chunks: chunks)
            case "0111": return .respond("7E8 03 41 11 40 AA AA AA AA\r\r>", chunks: chunks)
            default:
                if command.hasPrefix("AT") { return .respond("OK\r\r>", chunks: chunks) }
                return .respond("?\r\r>", chunks: chunks)
            }
        }
    }
}
