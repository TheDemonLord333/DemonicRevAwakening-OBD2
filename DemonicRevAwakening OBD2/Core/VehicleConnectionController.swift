//
//  VehicleConnectionController.swift
//  DemonicRevAwakening OBD2
//
//  Koordiniert die Datenquelle: Live (BLE/WLAN) oder Demo. Live- und
//  Demo-Betrieb schließen sich gegenseitig aus; Demo-Daten ersetzen niemals
//  stillschweigend eine unterbrochene Live-Verbindung.
//

import Foundation
import Observation

nonisolated enum DataSourceMode: Equatable, Sendable {
    case none
    case live
    case demo
}

/// Ziel einer Live-Verbindung.
nonisolated enum ConnectionTarget: Equatable, Sendable {
    case bluetooth(peripheralID: UUID, peripheralName: String, profile: BLEAdapterProfile)
    case wifi(host: String, port: Int)

    var displayName: String {
        switch self {
        case .bluetooth(_, let name, let profile):
            name == profile.name ? name : "\(name) (\(profile.name))"
        case .wifi(let host, let port):
            "WLAN \(host):\(port)"
        }
    }

    var kind: ConnectionKind {
        switch self {
        case .bluetooth: .bluetooth
        case .wifi: .wifi
        }
    }
}

nonisolated enum LinkState: Equatable, Sendable {
    case idle
    case connecting
    case initializing
    case streaming
    case reconnecting(attempt: Int, maxAttempts: Int, retryAt: Date)
    /// App im Hintergrund – Verbindung bewusst getrennt.
    case suspended
    case failed(String)

    var isActiveOrPending: Bool {
        switch self {
        case .connecting, .initializing, .streaming, .reconnecting: true
        case .idle, .suspended, .failed: false
        }
    }
}

@Observable
final class VehicleConnectionController {
    typealias TransportFactory = (ConnectionTarget) throws -> OBDTransport

    private(set) var mode: DataSourceMode = .none
    private(set) var linkState: LinkState = .idle
    private(set) var target: ConnectionTarget?
    private(set) var snapshot: VehicleSnapshot?
    private(set) var adapterInfo: AdapterInfo?
    private(set) var lastError: String?
    /// Status der letzten Drehzahlabfrage ohne gültigen Wert (z. B. NO DATA).
    private(set) var lastRPMStatus: ELM327Status?
    private(set) var pollingRateHz: Double?
    private(set) var demo = DemoEngine()

    var autoReconnect = true
    var reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30]
    var minimumPollInterval: Duration = .milliseconds(100)
    var noDataPollInterval: Duration = .milliseconds(400)
    var demoTickInterval: Duration = .milliseconds(33)
    var sessionConfiguration = OBDSession.Configuration()
    var staleAfter: TimeInterval = DemonInputResolver.defaultMaxAge

    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored private let transportFactory: TransportFactory
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var transport: OBDTransport?
    @ObservationIgnored private var session: OBDSession?
    @ObservationIgnored private var liveGeneration = 0
    @ObservationIgnored private var reachedStreaming = false
    @ObservationIgnored private var resumeTargetAfterBackground: ConnectionTarget?
    @ObservationIgnored private var resumeDemoAfterBackground = false

    init(transportFactory: @escaping TransportFactory) {
        self.transportFactory = transportFactory
    }

    // MARK: - Abgeleitete Zustände

    /// Liefert die Datenstrecke gerade (potenziell) gültige Werte?
    var isDataPathActive: Bool {
        switch mode {
        case .none: false
        case .demo: true
        case .live: linkState == .streaming
        }
    }

    /// Eine Sitzung gilt als aktiv, solange Live-Verbindung oder Demo laufen.
    var isSessionActive: Bool {
        switch mode {
        case .none: false
        case .demo: true
        case .live: linkState.isActiveOrPending
        }
    }

    func demonInput() -> DemonInput {
        DemonInputResolver.resolve(isDataPathActive: isDataPathActive, snapshot: snapshot,
                                   now: now(), maxAge: staleAfter)
    }

    func rpmFreshness() -> Freshness {
        Freshness(snapshot?.rpm, now: now(), maxAge: staleAfter)
    }

    // MARK: - Live-Verbindung

    func connect(to target: ConnectionTarget) {
        stopDemoTicker()
        stopLive()
        mode = .live
        self.target = target
        lastError = nil
        lastRPMStatus = nil
        adapterInfo = nil
        pollingRateHz = nil
        snapshot = VehicleSnapshot(origin: .live)
        linkState = .connecting
        let generation = liveGeneration
        liveTask = Task { [weak self] in
            await self?.runLive(target: target, generation: generation)
        }
    }

    /// Erneuter Versuch nach einem Fehler.
    func retry() {
        guard let target else { return }
        connect(to: target)
    }

    /// Trennt die Live-Verbindung bzw. bricht die Wiederverbindung ab.
    func disconnect() {
        stopLive()
        stopDemoTicker()
        mode = .none
        linkState = .idle
        target = nil
        snapshot = nil
        adapterInfo = nil
        pollingRateHz = nil
        lastRPMStatus = nil
        resumeTargetAfterBackground = nil
    }

    /// Bricht eine laufende Wiederverbindung ab, zeigt aber den letzten Fehler.
    func cancelReconnect() {
        let message = lastError ?? "Wiederverbindung abgebrochen."
        stopLive()
        linkState = .failed(message)
    }

    private func runLive(target: ConnectionTarget, generation: Int) async {
        var attempt = 0
        while !Task.isCancelled, generation == liveGeneration {
            reachedStreaming = false
            var failure: Error?
            do {
                try await runConnection(target: target, generation: generation)
            } catch {
                failure = error
            }
            // Ein abgebrochener Durchlauf darf eine inzwischen neu aufgebaute
            // Verbindung nicht abbauen – `stopLive()` hat bereits aufgeräumt.
            guard !Task.isCancelled, generation == liveGeneration else { return }
            teardownConnection()

            if reachedStreaming { attempt = 0 }
            let message = Self.describe(failure)
            lastError = message
            let retryable = (failure as? OBDSessionError)?.isRetryable ?? true
            guard autoReconnect, retryable, attempt < reconnectDelays.count else {
                linkState = .failed(message)
                return
            }
            let delay = reconnectDelays[attempt]
            attempt += 1
            linkState = .reconnecting(attempt: attempt, maxAttempts: reconnectDelays.count,
                                      retryAt: now().addingTimeInterval(delay))
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard generation == liveGeneration else { return }
            linkState = .connecting
        }
    }

    private func runConnection(target: ConnectionTarget, generation: Int) async throws {
        let transport = try transportFactory(target)
        let session = OBDSession(transport: transport, configuration: sessionConfiguration)
        self.transport = transport
        self.session = session
        transport.onClose = { [weak session] error in
            let reason = error.map { Self.describe($0) } ?? "Gerät hat die Verbindung beendet."
            session?.close(reason: .linkLost(reason))
        }

        try await transport.open()
        try Task.checkCancellation()
        linkState = .initializing
        let info = try await session.initialize()
        try Task.checkCancellation()
        adapterInfo = info
        linkState = .streaming
        lastError = nil
        reachedStreaming = true

        while !Task.isCancelled, generation == liveGeneration {
            let cycleStart = ContinuousClock.now
            let result = try await session.pollOnce()
            guard generation == liveGeneration, mode == .live else { return }
            apply(result)
            let interval = result.rpm == nil ? noDataPollInterval : minimumPollInterval
            let elapsed = ContinuousClock.now - cycleStart
            if elapsed < interval {
                try await Task.sleep(for: interval - elapsed)
            }
            updatePollingRate(cycle: ContinuousClock.now - cycleStart)
        }
        throw CancellationError()
    }

    private func apply(_ result: OBDPollResult) {
        let timestamp = now()
        var updated = snapshot ?? VehicleSnapshot(origin: .live)
        updated.origin = .live
        if let rpm = result.rpm {
            updated.rpm = TimedValue(value: rpm, timestamp: timestamp)
            lastRPMStatus = nil
        } else if let status = result.rpmStatus {
            lastRPMStatus = status
        } else if result.rpmTimedOut {
            lastRPMStatus = .error("Zeitüberschreitung")
        }
        for (pid, value) in result.supplementary {
            let timed = TimedValue(value: value, timestamp: timestamp)
            switch pid {
            case .vehicleSpeed: updated.speedKmh = timed
            case .engineLoad: updated.engineLoadPercent = timed
            case .throttlePosition: updated.throttlePercent = timed
            case .engineRPM, .supported01To20: break
            }
        }
        snapshot = updated
    }

    private func updatePollingRate(cycle: Duration) {
        let seconds = Double(cycle.components.seconds) + Double(cycle.components.attoseconds) / 1e18
        guard seconds > 0 else { return }
        let rate = 1 / seconds
        pollingRateHz = pollingRateHz.map { $0 * 0.8 + rate * 0.2 } ?? rate
    }

    private func stopLive() {
        liveGeneration += 1
        liveTask?.cancel()
        liveTask = nil
        teardownConnection()
    }

    private func teardownConnection() {
        session?.close()
        session = nil
        if let transport {
            transport.onClose = nil
            transport.close()
        }
        transport = nil
    }

    // MARK: - Demo

    func startDemo() {
        stopLive()
        mode = .demo
        linkState = .idle
        target = nil
        adapterInfo = nil
        lastError = nil
        lastRPMStatus = nil
        pollingRateHz = nil
        demo.restart()
        snapshot = demoSnapshot()
        startDemoTicker()
    }

    func stopDemo() {
        guard mode == .demo else { return }
        stopDemoTicker()
        mode = .none
        snapshot = nil
    }

    func setDemoMode(_ newMode: DemoEngine.Mode) { demo.setMode(newMode) }
    func setDemoManualRPM(_ rpm: Double) { demo.manualTargetRPM = rpm }
    func pauseDemo() { demo.pause() }
    func resumeDemo() { demo.resume() }

    func restartDemo() {
        demo.restart()
        if mode == .demo { snapshot = demoSnapshot() }
    }

    private func startDemoTicker() {
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.demoTickInterval ?? .milliseconds(33))
                guard let self, !Task.isCancelled, self.mode == .demo else { return }
                let current = ContinuousClock.now
                let elapsed = current - last
                last = current
                let dt = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                self.demo.advance(by: dt)
                self.snapshot = self.demoSnapshot()
            }
        }
    }

    private func stopDemoTicker() {
        demoTask?.cancel()
        demoTask = nil
    }

    private func demoSnapshot() -> VehicleSnapshot {
        let timestamp = now()
        return VehicleSnapshot(origin: .demo,
                               rpm: TimedValue(value: demo.rpm, timestamp: timestamp),
                               speedKmh: TimedValue(value: demo.speedKmh, timestamp: timestamp),
                               engineLoadPercent: TimedValue(value: demo.engineLoadPercent, timestamp: timestamp),
                               throttlePercent: nil)
    }

    // MARK: - Lebenszyklus

    /// App geht in den Hintergrund: keine Hintergrundverbindung, keine
    /// Hintergrundanimation. Die Sitzung wird sauber pausiert.
    func enterBackground() {
        switch mode {
        case .live:
            if linkState.isActiveOrPending, let target {
                resumeTargetAfterBackground = target
                stopLive()
                linkState = .suspended
            }
        case .demo:
            resumeDemoAfterBackground = !demo.isPaused
            demo.pause()
            stopDemoTicker()
        case .none:
            break
        }
    }

    /// App wieder im Vordergrund: pausierte Sitzung fortsetzen.
    func enterForeground() {
        switch mode {
        case .live:
            if linkState == .suspended, let resumeTarget = resumeTargetAfterBackground {
                resumeTargetAfterBackground = nil
                connect(to: resumeTarget)
            }
        case .demo:
            if resumeDemoAfterBackground { demo.resume() }
            resumeDemoAfterBackground = false
            if demoTask == nil { startDemoTicker() }
        case .none:
            break
        }
    }

    // MARK: - Hilfen

    static func describe(_ error: Error?) -> String {
        guard let error else { return "Verbindung beendet." }
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}
