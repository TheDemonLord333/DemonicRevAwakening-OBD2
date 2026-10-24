//
//  OBDSession.swift
//  DemonicRevAwakening OBD2
//
//  ELM327-Protokollschicht über einem beliebigen `OBDTransport`:
//  Initialisierung, serielle Befehlswarteschlange, Zeitlimits,
//  Ermittlung unterstützter PIDs und priorisierte Drehzahlabfrage.
//
//  Die Session sendet ausschließlich lesende AT-Konfigurationsbefehle und
//  Mode-01-Abfragen. Es werden keine Fehlercodes gelöscht (kein Mode 04)
//  und keine Steuer- oder Codierbefehle gesendet.
//

import Foundation

nonisolated enum OBDSessionError: LocalizedError, Equatable, Sendable {
    case timeout(command: String)
    case adapterNotResponding
    case vehicleNotResponding(String)
    case rpmNotSupported
    case linkLost(String)
    case closed

    /// Ob ein erneuter Verbindungsversuch sinnvoll ist.
    var isRetryable: Bool {
        switch self {
        case .rpmNotSupported, .closed: false
        default: true
        }
    }

    var errorDescription: String? {
        switch self {
        case .timeout(let command):
            "Keine Antwort des Adapters auf „\(command)“ (Zeitüberschreitung)."
        case .adapterNotResponding:
            "Der Adapter antwortet nicht wie ein ELM327-kompatibler OBD2-Adapter."
        case .vehicleNotResponding(let reason):
            "Das Fahrzeug antwortet nicht: \(reason). Ist die Zündung eingeschaltet?"
        case .rpmNotSupported:
            "Das Fahrzeug liefert über diesen Adapter keine Motordrehzahl (PID 0C)."
        case .linkLost(let reason):
            "Verbindung zum Adapter verloren: \(reason)"
        case .closed:
            "Die Sitzung wurde beendet."
        }
    }
}

/// Informationen nach erfolgreicher Initialisierung.
nonisolated struct AdapterInfo: Equatable, Sendable {
    var identity: String?
    var protocolName: String?
    var supportedPIDs: Set<UInt8>
    var headersEnabled: Bool

    func supports(_ pid: OBDPID) -> Bool { supportedPIDs.contains(pid.rawValue) }
}

/// Ergebnis eines Abfragezyklus.
nonisolated struct OBDPollResult: Equatable, Sendable {
    var rpm: Double?
    /// Status, falls keine gültige Drehzahl empfangen wurde.
    var rpmStatus: ELM327Status?
    var rpmTimedOut = false
    var supplementary: [OBDPID: Double] = [:]
}

final class OBDSession {
    struct Configuration: Sendable {
        var resetTimeout: Duration = .seconds(5)
        var commandTimeout: Duration = .seconds(2)
        /// Erste Fahrzeugabfrage: Der Adapter sucht ggf. das Protokoll.
        var searchTimeout: Duration = .seconds(15)
        /// Nach einer Zeitüberschreitung verspätete Antworten verwerfen.
        var drainDuration: Duration = .milliseconds(300)
        var wakeUpDelay: Duration = .milliseconds(200)
        var maxConsecutiveTimeouts = 4
        var maxConsecutiveBusErrors = 12
        /// Jede n-te Runde wird ein Zusatzwert abgefragt; Drehzahl hat Vorrang.
        var supplementaryEvery = 3
        /// Fehlende Antworten des gewählten Steuergeräts, bevor neu gewählt wird.
        var ecuRelockAfterMisses = 3
    }

    let configuration: Configuration
    private let transport: OBDTransport
    private var assembler = ELM327ResponseAssembler()
    private let inFlight = PendingOperation<ELM327Reply>()
    private var inFlightCommand: String?
    private var discardUntil: ContinuousClock.Instant?

    // Serielle Warteschlange: Es ist immer höchstens ein Befehl unterwegs.
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private(set) var isClosed = false
    /// Grund des Schließens; wird für alle späteren Befehle erneut geworfen.
    private var closeReason: OBDSessionError = .closed
    private(set) var adapterInfo: AdapterInfo?
    /// Gleitender Mittelwert der Antwortzeit in Sekunden.
    private(set) var averageResponseTime: TimeInterval?
    /// Steuergerät, dessen Drehzahl verwendet wird.
    private(set) var lockedECU: String?

    private var lockedECUMisses = 0
    private var consecutiveTimeouts = 0
    private var consecutiveBusErrors = 0
    private var cycleCount = 0
    private var supplementaryIndex = 0

    init(transport: OBDTransport, configuration: Configuration = Configuration()) {
        self.transport = transport
        self.configuration = configuration
        transport.onReceive = { [weak self] data in
            self?.handleIncoming(data)
        }
    }

    // MARK: - Initialisierung

    func initialize() async throws -> AdapterInfo {
        do {
            return try await performInitialization()
        } catch OBDSessionError.timeout {
            throw OBDSessionError.adapterNotResponding
        }
    }

    private func performInitialization() async throws -> AdapterInfo {
        // Ein einzelnes CR weckt manche Adapter und erzeugt einen Prompt,
        // der hier bewusst verworfen wird.
        try await transport.write(Data("\r".utf8))
        try await Task.sleep(for: configuration.wakeUpDelay)
        assembler.reset()

        var identity: String?
        do {
            let reset = try await send("ATZ", timeout: configuration.resetTimeout)
            identity = Self.identity(in: reset.lines)
        } catch OBDSessionError.timeout {
            // Manche Klone liefern nach ATZ keinen Prompt; ATI als Ersatz.
            let info = try await send("ATI", timeout: configuration.commandTimeout)
            identity = Self.identity(in: info.lines)
        }

        var headersEnabled = false
        let setup: [String] = ["ATE0", "ATL0", "ATS1", "ATH1", "ATAT1", "ATSP0"]
        for command in setup {
            let reply = try await send(command, timeout: configuration.commandTimeout)
            if command == "ATH1" { headersEnabled = reply.status == .ok }
            if command == "ATE0" || command == "ATSP0", reply.status == .unknownCommand {
                throw OBDSessionError.adapterNotResponding
            }
        }

        let supportedReply = try await send(OBDPID.supported01To20.command, timeout: configuration.searchTimeout)
        let frames = OBDResponseDecoder.frames(for: .supported01To20, in: supportedReply.lines)
        guard !frames.isEmpty else {
            let status = supportedReply.status ?? .dataError
            throw OBDSessionError.vehicleNotResponding(status.description)
        }
        var supported = Set<UInt8>()
        for frame in frames {
            supported.formUnion(OBDResponseDecoder.supportedPIDs(base: 0x00, bitmask: frame.data))
        }

        let protocolName = (try? await send("ATDP", timeout: configuration.commandTimeout))?.lines.first

        if !supported.contains(OBDPID.engineRPM.rawValue) {
            // Bitmaske meldet PID 0C nicht – einmal direkt prüfen.
            let probe = try await send(OBDPID.engineRPM.command, timeout: configuration.commandTimeout)
            guard selectRPM(from: probe) != nil else { throw OBDSessionError.rpmNotSupported }
            supported.insert(OBDPID.engineRPM.rawValue)
        }

        let info = AdapterInfo(identity: identity, protocolName: protocolName,
                               supportedPIDs: supported, headersEnabled: headersEnabled)
        adapterInfo = info
        return info
    }

    private static func identity(in lines: [String]) -> String? {
        lines.last { line in
            let upper = line.uppercased()
            return upper.contains("ELM") || upper.contains("STN") || upper.contains("OBDLINK")
        } ?? lines.last
    }

    // MARK: - Abfragezyklus

    /// Fragt die Drehzahl ab und gelegentlich einen unterstützten Zusatzwert.
    func pollOnce() async throws -> OBDPollResult {
        var result = OBDPollResult()

        do {
            let reply = try await send(OBDPID.engineRPM.command, timeout: configuration.commandTimeout)
            consecutiveTimeouts = 0
            if let rpm = selectRPM(from: reply) {
                result.rpm = rpm
                consecutiveBusErrors = 0
            } else {
                let status = reply.status ?? .dataError
                result.rpmStatus = status
                try trackFailure(status)
            }
        } catch OBDSessionError.timeout {
            result.rpmTimedOut = true
            try registerTimeout()
        }

        cycleCount += 1
        if cycleCount % max(configuration.supplementaryEvery, 1) == 0, let pid = nextSupplementaryPID() {
            do {
                let reply = try await send(pid.command, timeout: configuration.commandTimeout)
                consecutiveTimeouts = 0
                if let value = selectValue(for: pid, from: reply) {
                    result.supplementary[pid] = value
                }
                if reply.status == .adapterReset {
                    try trackFailure(.adapterReset)
                }
            } catch OBDSessionError.timeout {
                try registerTimeout()
            }
        }
        return result
    }

    private func registerTimeout() throws {
        consecutiveTimeouts += 1
        if consecutiveTimeouts >= configuration.maxConsecutiveTimeouts {
            throw OBDSessionError.linkLost("Der Adapter antwortet nicht mehr.")
        }
    }

    private func trackFailure(_ status: ELM327Status) throws {
        switch status {
        case .adapterReset:
            throw OBDSessionError.linkLost(status.description)
        case .unableToConnect, .canError, .busError, .busInitError:
            consecutiveBusErrors += 1
            if consecutiveBusErrors >= configuration.maxConsecutiveBusErrors {
                throw OBDSessionError.vehicleNotResponding(status.description)
            }
        default:
            // NO DATA, STOPPED usw.: kein Abbruch, der Wert veraltet sichtbar.
            break
        }
    }

    private func nextSupplementaryPID() -> OBDPID? {
        let candidates: [OBDPID] = [.vehicleSpeed, .engineLoad, .throttlePosition]
            .filter { adapterInfo?.supports($0) ?? false }
        guard !candidates.isEmpty else { return nil }
        let pid = candidates[supplementaryIndex % candidates.count]
        supplementaryIndex += 1
        return pid
    }

    // MARK: - Auswahl einer konsistenten Datenquelle

    /// Wählt bei mehreren Steuergeräteantworten konsistent dasselbe Gerät.
    /// Bevorzugt wird das Motorsteuergerät 7E8 (CAN 11 Bit), sonst die
    /// erste Antwort in sortierter Reihenfolge.
    func selectRPM(from reply: ELM327Reply) -> Double? {
        let frames = OBDResponseDecoder.frames(for: .engineRPM, in: reply.lines)
        guard !frames.isEmpty else { return nil }

        if let locked = lockedECU {
            if let frame = frames.first(where: { $0.ecu == locked }) {
                lockedECUMisses = 0
                return OBDPID.engineRPM.decode(frame.data)
            }
            lockedECUMisses += 1
            guard lockedECUMisses >= configuration.ecuRelockAfterMisses else { return nil }
        }
        let chosen = frames.first(where: { $0.ecu == "7E8" })
            ?? frames.min(by: { $0.ecu < $1.ecu })
        lockedECU = chosen?.ecu
        lockedECUMisses = 0
        return chosen.flatMap { OBDPID.engineRPM.decode($0.data) }
    }

    private func selectValue(for pid: OBDPID, from reply: ELM327Reply) -> Double? {
        let frames = OBDResponseDecoder.frames(for: pid, in: reply.lines)
        let frame = frames.first(where: { $0.ecu == lockedECU }) ?? frames.min(by: { $0.ecu < $1.ecu })
        return frame.flatMap { pid.decode($0.data) }
    }

    // MARK: - Serielle Befehlsausführung

    /// Sendet einen Befehl und wartet auf die vollständige Antwort bis zum
    /// Prompt. Weitere Aufrufe warten, bis der vorherige abgeschlossen ist.
    func send(_ command: String, timeout: Duration) async throws -> ELM327Reply {
        await acquire()
        defer { release() }
        guard !isClosed else { throw closeReason }
        try Task.checkCancellation()

        if let until = discardUntil {
            if until > .now { try await Task.sleep(until: until, clock: .continuous) }
            discardUntil = nil
            assembler.reset()
        }

        let started = ContinuousClock.now
        let payload = Data((command + "\r").utf8)
        do {
            let reply = try await inFlight.run(timeout: timeout,
                                               timeoutError: OBDSessionError.timeout(command: command)) {
                inFlightCommand = command
                Task { [weak self] in
                    do {
                        try await self?.transport.write(payload)
                    } catch {
                        self?.inFlight.fail(error)
                    }
                }
            }
            inFlightCommand = nil
            recordResponseTime(ContinuousClock.now - started)
            return reply
        } catch OBDSessionError.timeout(let failedCommand) {
            inFlightCommand = nil
            // Eine verspätete Antwort darf nicht dem nächsten Befehl zugeordnet werden.
            discardUntil = .now + configuration.drainDuration
            assembler.reset()
            throw OBDSessionError.timeout(command: failedCommand)
        } catch {
            inFlightCommand = nil
            throw error
        }
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            // Übergabe an den nächsten Wartenden; `isBusy` bleibt gesetzt.
            waiters.removeFirst().resume()
        }
    }

    private func handleIncoming(_ data: Data) {
        if let until = discardUntil, until > .now {
            return
        }
        for raw in assembler.append(data) {
            guard let command = inFlightCommand, inFlight.isPending else { continue }
            inFlightCommand = nil
            inFlight.succeed(ELM327ReplyParser.parse(raw, command: command))
        }
    }

    private func recordResponseTime(_ duration: Duration) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        if let average = averageResponseTime {
            averageResponseTime = average * 0.8 + seconds * 0.2
        } else {
            averageResponseTime = seconds
        }
    }

    /// Beendet die Session; laufende und wartende Befehle schlagen fehl.
    func close(reason: OBDSessionError = .closed) {
        guard !isClosed else { return }
        isClosed = true
        closeReason = reason
        transport.onReceive = nil
        inFlightCommand = nil
        inFlight.fail(reason)
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
