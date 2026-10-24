//
//  ELM327Parser.swift
//  DemonicRevAwakening OBD2
//
//  Puffert Antwort-Fragmente bis zum ELM327-Prompt („>“) und zerlegt
//  vollständige Antworten in Datenzeilen und Statusmeldungen.
//

import Foundation

/// Sammelt eingehende Bytes und liefert vollständige Antworten, sobald
/// der Prompt `>` empfangen wurde.
nonisolated struct ELM327ResponseAssembler: Sendable {
    /// Schutz vor unbegrenztem Wachstum bei fehlerhaften Datenströmen.
    static let maximumBufferLength = 8_192

    private var buffer = ""

    var hasPendingData: Bool { !buffer.isEmpty }

    /// Hängt empfangene Bytes an und gibt alle jetzt vollständigen Antworten
    /// (ohne Prompt) zurück.
    mutating func append(_ data: Data) -> [String] {
        // ELM327-Klone senden gelegentlich NUL-Bytes oder Bytes > 0x7F.
        let filtered = data.filter { $0 != 0 && $0 < 0x80 }
        buffer += String(decoding: filtered, as: UTF8.self)

        var responses: [String] = []
        while let promptIndex = buffer.firstIndex(of: ">") {
            responses.append(String(buffer[..<promptIndex]))
            buffer = String(buffer[buffer.index(after: promptIndex)...])
        }
        if buffer.count > Self.maximumBufferLength {
            buffer = String(buffer.suffix(Self.maximumBufferLength))
        }
        return responses
    }

    mutating func reset() { buffer = "" }
}

/// Status- und Fehlermeldungen des Adapters.
nonisolated enum ELM327Status: Equatable, Sendable {
    case ok
    case noData
    case stopped
    case unableToConnect
    case canError
    case busError
    case busBusy
    case busInitError
    case dataError
    case bufferFull
    case unknownCommand
    case adapterReset
    case error(String)

    var isError: Bool { self != .ok }

    var description: String {
        switch self {
        case .ok: "OK"
        case .noData: "NO DATA – das Fahrzeug hat nicht geantwortet"
        case .stopped: "STOPPED – Abfrage unterbrochen"
        case .unableToConnect: "UNABLE TO CONNECT – kein OBD-Protokoll gefunden (Zündung an?)"
        case .canError: "CAN ERROR – Problem auf dem CAN-Bus"
        case .busError: "BUS ERROR – Problem auf dem Fahrzeugbus"
        case .busBusy: "BUS BUSY – Fahrzeugbus ausgelastet"
        case .busInitError: "BUS INIT ERROR – Businitialisierung fehlgeschlagen"
        case .dataError: "DATA ERROR – fehlerhafte Antwort"
        case .bufferFull: "BUFFER FULL – Adapterpuffer übergelaufen"
        case .unknownCommand: "? – Befehl vom Adapter nicht unterstützt"
        case .adapterReset: "Adapter wurde zurückgesetzt (Spannungs- oder Aktivitätsmeldung)"
        case .error(let text): text
        }
    }
}

/// Eine vollständig ausgewertete Antwort auf einen Befehl.
nonisolated struct ELM327Reply: Equatable, Sendable {
    var command: String
    /// Datenzeilen ohne Echo, Leerzeilen und Statusmeldungen.
    var lines: [String]
    /// Erste gefundene Statusmeldung, falls vorhanden.
    var status: ELM327Status?
    /// `true`, wenn der Adapter „SEARCHING...“ gemeldet hat.
    var didSearch: Bool

    var isOK: Bool { status == nil || status == .ok }
}

nonisolated enum ELM327ReplyParser {
    /// Zerlegt eine Rohantwort (ohne Prompt) für `command`.
    static func parse(_ raw: String, command: String) -> ELM327Reply {
        let normalizedCommand = normalize(command)
        var lines: [String] = []
        var status: ELM327Status?
        var didSearch = false

        let rawLines = raw
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for (index, line) in rawLines.enumerated() {
            let upper = line.uppercased()
            let compact = normalize(line)

            // Echo (bei aktivem ATE1 oder vor ATE0) entfernen.
            if index == 0, !normalizedCommand.isEmpty, compact == normalizedCommand {
                continue
            }
            if upper.hasPrefix("SEARCHING") {
                didSearch = true
                continue
            }
            if upper.hasPrefix("BUS INIT") {
                if upper.contains("ERROR") { status = status ?? .busInitError }
                continue
            }
            if let lineStatus = classify(upper) {
                if lineStatus == .ok {
                    status = status ?? .ok
                } else if status == nil || status == .ok {
                    status = lineStatus
                }
                continue
            }
            // Zeilen mit angehängtem Fehlerkennzeichen sind unbrauchbar.
            if upper.contains("<DATA ERROR") || upper.contains("<RX ERROR") {
                if status == nil || status == .ok { status = .dataError }
                continue
            }
            lines.append(line)
        }
        return ELM327Reply(command: command, lines: lines, status: status, didSearch: didSearch)
    }

    static func classify(_ upperLine: String) -> ELM327Status? {
        let compact = upperLine.replacingOccurrences(of: " ", with: "")
        switch compact {
        case "OK": return .ok
        case "NODATA": return .noData
        case "STOPPED": return .stopped
        case "?": return .unknownCommand
        case "BUFFERFULL": return .bufferFull
        case "BUSBUSY": return .busBusy
        case "BUSERROR", "FBERROR": return .busError
        case "CANERROR": return .canError
        case "DATAERROR": return .dataError
        case "ERROR": return .error("ERROR")
        case "ACTALERT", "LVRESET", "LPALERT": return .adapterReset
        default: break
        }
        if compact.hasPrefix("UNABLETOCONNECT") { return .unableToConnect }
        if compact.hasPrefix("ERR"), compact.count <= 6, compact.dropFirst(3).allSatisfy(\.isNumber) {
            return .error(upperLine)
        }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.uppercased().filter { !$0.isWhitespace }
    }
}
