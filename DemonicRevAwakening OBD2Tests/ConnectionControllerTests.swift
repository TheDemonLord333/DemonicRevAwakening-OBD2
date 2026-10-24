//
//  ConnectionControllerTests.swift
//  DemonicRevAwakening OBD2Tests
//
//  Trennung von Demo- und Live-Betrieb, veraltete Daten und Wiederverbindung.
//

import Foundation
import Testing
@testable import DemonicRevAwakening_OBD2

@MainActor
struct ConnectionControllerTests {
    private let wifiTarget = ConnectionTarget.wifi(host: "192.168.0.10", port: 35_000)

    private func makeController(transports: @escaping () -> MockELMTransport) -> VehicleConnectionController {
        let controller = VehicleConnectionController { _ in transports() }
        var configuration = OBDSession.Configuration()
        configuration.resetTimeout = .milliseconds(300)
        configuration.commandTimeout = .milliseconds(150)
        configuration.searchTimeout = .milliseconds(300)
        configuration.drainDuration = .milliseconds(20)
        configuration.wakeUpDelay = .milliseconds(5)
        configuration.maxConsecutiveTimeouts = 2
        controller.sessionConfiguration = configuration
        controller.minimumPollInterval = .milliseconds(20)
        controller.noDataPollInterval = .milliseconds(20)
        controller.reconnectDelays = [0.05, 0.05]
        controller.demoTickInterval = .milliseconds(10)
        return controller
    }

    /// Wartet, bis `condition` erfüllt ist (höchstens `timeout`).
    private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func liveConnectionStreamsRealRPM() async {
        let transport = MockELMTransport()
        let controller = makeController { transport }
        controller.connect(to: wifiTarget)
        #expect(await waitUntil { controller.snapshot?.rpm != nil })
        #expect(controller.mode == .live)
        #expect(controller.linkState == .streaming)
        #expect(controller.snapshot?.origin == .live)
        #expect(controller.snapshot?.rpm?.value == 1_726)
        #expect(controller.demonInput() == .rpm(1_726))
        controller.disconnect()
        #expect(transport.isClosed)
        #expect(controller.demonInput() == .noConnection)
    }

    @Test func connectedWithoutDataIsAwaitingData() async {
        let transport = MockELMTransport()
        let healthy = MockELMTransport.healthyCar(rpmHex: "1A F8")
        transport.handler = { command in
            command == "010C" ? .respond("NO DATA\r\r>") : healthy(command)
        }
        let controller = makeController { transport }
        controller.connect(to: wifiTarget)
        #expect(await waitUntil { controller.lastRPMStatus == .noData })
        #expect(controller.linkState == .streaming)
        #expect(controller.snapshot?.rpm == nil)
        #expect(controller.demonInput() == .awaitingData)
        controller.disconnect()
    }

    @Test func staleRPMIsNotUsed() async {
        let transport = MockELMTransport()
        let controller = makeController { transport }
        var clock = Date()
        controller.now = { clock }
        controller.connect(to: wifiTarget)
        #expect(await waitUntil { controller.snapshot?.rpm != nil })
        let healthy = MockELMTransport.healthyCar(rpmHex: "1A F8")
        transport.handler = { command in
            command == "010C" ? .respond("NO DATA\r\r>") : healthy(command)
        }
        try? await Task.sleep(for: .milliseconds(80))
        clock = clock.addingTimeInterval(10)
        if case .stale(let age) = controller.rpmFreshness() {
            #expect(abs(age - 10) < 0.01)
        } else {
            Issue.record("Drehzahl hätte als veraltet gelten müssen")
        }
        #expect(controller.demonInput() == .awaitingData)
        controller.disconnect()
    }

    @Test func linkLossNeverFallsBackToDemo() async {
        var created: [MockELMTransport] = []
        let controller = makeController {
            let transport = MockELMTransport()
            if !created.isEmpty { transport.openError = TransportError.connectionTimeout }
            created.append(transport)
            return transport
        }
        controller.connect(to: wifiTarget)
        #expect(await waitUntil { controller.linkState == .streaming })
        created.first?.simulateDisconnect()

        #expect(await waitUntil {
            if case .reconnecting = controller.linkState { return true }
            return false
        })
        #expect(controller.mode == .live)
        #expect(controller.snapshot?.origin == .live)
        #expect(controller.demonInput() == .noConnection)

        #expect(await waitUntil {
            if case .failed = controller.linkState { return true }
            return false
        })
        #expect(controller.mode == .live)
        #expect(controller.snapshot?.origin != .demo)
        #expect(controller.demonInput() == .noConnection)
        #expect(created.count == 3) // Erstverbindung + 2 Versuche
    }

    @Test func autoReconnectDisabledFailsImmediately() async {
        let controller = makeController {
            let transport = MockELMTransport()
            transport.openError = TransportError.connectionTimeout
            return transport
        }
        controller.autoReconnect = false
        controller.connect(to: wifiTarget)
        #expect(await waitUntil {
            if case .failed = controller.linkState { return true }
            return false
        })
        #expect(controller.lastError == TransportError.connectionTimeout.errorDescription)
    }

    @Test func reconnectSucceedsAfterTransientFailure() async {
        var count = 0
        let controller = makeController {
            count += 1
            let transport = MockELMTransport()
            if count == 1 { transport.openError = TransportError.connectionTimeout }
            return transport
        }
        controller.connect(to: wifiTarget)
        #expect(await waitUntil { controller.linkState == .streaming })
        #expect(count == 2)
        controller.disconnect()
    }

    @Test func cancelReconnectStopsAttempts() async {
        var count = 0
        let controller = makeController {
            count += 1
            let transport = MockELMTransport()
            transport.openError = TransportError.connectionTimeout
            return transport
        }
        controller.reconnectDelays = [0.3, 0.3, 0.3]
        controller.connect(to: wifiTarget)
        #expect(await waitUntil {
            if case .reconnecting = controller.linkState { return true }
            return false
        })
        controller.cancelReconnect()
        let attempts = count
        try? await Task.sleep(for: .milliseconds(500))
        #expect(count == attempts)
        if case .failed = controller.linkState {} else { Issue.record("Erwartet: failed") }
    }

    @Test func demoIsAlwaysMarkedAndReplacesLiveOnlyExplicitly() async {
        let transport = MockELMTransport()
        let controller = makeController { transport }
        controller.connect(to: wifiTarget)
        #expect(await waitUntil { controller.linkState == .streaming })

        controller.startDemo()
        #expect(transport.isClosed)
        #expect(controller.mode == .demo)
        #expect(controller.linkState == .idle)
        #expect(await waitUntil { (controller.demo.scenarioTime) > 0 })
        #expect(controller.snapshot?.origin == .demo)
        #expect(controller.isDataPathActive)

        controller.stopDemo()
        #expect(controller.mode == .none)
        #expect(controller.snapshot == nil)
        #expect(controller.demonInput() == .noConnection)
    }

    @Test func liveConnectionEndsDemo() async {
        let transport = MockELMTransport()
        let controller = makeController { transport }
        controller.startDemo()
        controller.connect(to: wifiTarget)
        #expect(controller.mode == .live)
        #expect(controller.snapshot?.origin == .live)
        #expect(controller.snapshot?.rpm == nil)
        let scenario = controller.demo.scenarioTime
        try? await Task.sleep(for: .milliseconds(80))
        #expect(controller.demo.scenarioTime == scenario)
        #expect(controller.snapshot?.origin == .live)
        controller.disconnect()
    }

    @Test func manualDemoUsesSlider() async {
        let controller = makeController { MockELMTransport() }
        controller.startDemo()
        controller.setDemoMode(.manual)
        controller.setDemoManualRPM(4_200)
        #expect(await waitUntil { abs((controller.snapshot?.rpm?.value ?? 0) - 4_200) < 5 })
        controller.pauseDemo()
        #expect(controller.demo.isPaused)
        controller.stopDemo()
    }

    @Test func backgroundSuspendsAndForegroundResumes() async {
        var count = 0
        let controller = makeController {
            count += 1
            return MockELMTransport()
        }
        controller.connect(to: wifiTarget)
        #expect(await waitUntil { controller.linkState == .streaming })
        controller.enterBackground()
        #expect(controller.linkState == .suspended)
        #expect(controller.demonInput() == .noConnection)
        controller.enterForeground()
        #expect(await waitUntil { controller.linkState == .streaming })
        #expect(count == 2)
        controller.disconnect()
    }
}
