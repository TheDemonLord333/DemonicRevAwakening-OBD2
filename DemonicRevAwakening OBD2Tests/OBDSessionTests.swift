//
//  OBDSessionTests.swift
//  DemonicRevAwakening OBD2Tests
//

import Foundation
import Testing
@testable import DemonicRevAwakening_OBD2

@MainActor
struct OBDSessionTests {
    private func fastConfiguration() -> OBDSession.Configuration {
        var configuration = OBDSession.Configuration()
        // Großzügig, damit ausgelastete CI-Simulatoren keine Zeitüberschreitung auslösen.
        configuration.resetTimeout = .seconds(2)
        configuration.commandTimeout = .seconds(2)
        configuration.searchTimeout = .seconds(2)
        configuration.drainDuration = .milliseconds(50)
        configuration.wakeUpDelay = .milliseconds(5)
        return configuration
    }

    @Test func initializesAndReadsSupportedPIDs() async throws {
        let transport = MockELMTransport()
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        let info = try await session.initialize()
        #expect(info.identity == "ELM327 v1.5")
        #expect(info.protocolName == "AUTO, ISO 15765-4 (CAN 11/500)")
        #expect(info.headersEnabled)
        #expect(info.supports(.engineRPM))
        #expect(info.supports(.vehicleSpeed))
        #expect(info.supports(.engineLoad))
        #expect(info.supports(.throttlePosition))
        // Nur lesende Befehle: AT-Konfiguration und Mode 01.
        #expect(transport.writtenCommands.allSatisfy { $0.hasPrefix("AT") || $0.hasPrefix("01") })
        #expect(!transport.writtenCommands.contains { $0.hasPrefix("04") })
    }

    @Test func pollsRPMFromFragmentedResponses() async throws {
        let transport = MockELMTransport()
        transport.handler = MockELMTransport.healthyCar(rpmHex: "0B 20", chunks: 5)
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        _ = try await session.initialize()
        let result = try await session.pollOnce()
        #expect(result.rpm == 712)
        #expect(session.lockedECU == "7E8")
    }

    @Test func supplementaryValuesOnlyWhenSupported() async throws {
        let transport = MockELMTransport()
        // Nur PIDs 01, 0C und 0D werden gemeldet.
        transport.handler = MockELMTransport.healthyCar(rpmHex: "1A F8", supportedMask: "80 18 00 00")
        var configuration = fastConfiguration()
        configuration.supplementaryEvery = 1
        let session = OBDSession(transport: transport, configuration: configuration)
        let info = try await session.initialize()
        #expect(info.supports(.engineRPM))
        #expect(info.supports(.vehicleSpeed))
        #expect(!info.supports(.engineLoad))
        #expect(!info.supports(.throttlePosition))

        for _ in 0..<4 {
            let result = try await session.pollOnce()
            #expect(result.rpm == 1_726)
            #expect(Set(result.supplementary.keys).isSubset(of: [.vehicleSpeed]))
        }
        #expect(!transport.writtenCommands.contains("0104"))
        #expect(!transport.writtenCommands.contains("0111"))
        #expect(transport.writtenCommands.contains("010D"))
    }

    @Test func rpmNotSupportedFailsInitialization() async throws {
        let transport = MockELMTransport()
        let healthy = MockELMTransport.healthyCar(rpmHex: "00 00", supportedMask: "80 08 00 00")
        transport.handler = { command in
            command == "010C" ? .respond("NO DATA\r\r>") : healthy(command)
        }
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        await #expect(throws: OBDSessionError.rpmNotSupported) {
            _ = try await session.initialize()
        }
    }

    @Test func silentAdapterIsReported() async throws {
        let transport = MockELMTransport()
        transport.handler = { _ in .silent }
        var configuration = fastConfiguration()
        configuration.resetTimeout = .milliseconds(300)
        configuration.commandTimeout = .milliseconds(200)
        let session = OBDSession(transport: transport, configuration: configuration)
        await #expect(throws: OBDSessionError.adapterNotResponding) {
            _ = try await session.initialize()
        }
    }

    @Test func unableToConnectIsReported() async throws {
        let transport = MockELMTransport()
        let healthy = MockELMTransport.healthyCar(rpmHex: "00 00")
        transport.handler = { command in
            command == "0100" ? .respond("SEARCHING...\rUNABLE TO CONNECT\r\r>") : healthy(command)
        }
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        await #expect(throws: OBDSessionError.vehicleNotResponding(ELM327Status.unableToConnect.description)) {
            _ = try await session.initialize()
        }
    }

    @Test func noDataYieldsNoInventedRPM() async throws {
        let transport = MockELMTransport()
        let healthy = MockELMTransport.healthyCar(rpmHex: "1A F8")
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        _ = try await session.initialize()
        transport.handler = { command in
            command == "010C" ? .respond("NO DATA\r\r>") : healthy(command)
        }
        let result = try await session.pollOnce()
        #expect(result.rpm == nil)
        #expect(result.rpmStatus == .noData)
    }

    @Test func timeoutsAreCountedAndLinkLossThrown() async throws {
        let transport = MockELMTransport()
        var configuration = fastConfiguration()
        configuration.maxConsecutiveTimeouts = 3
        configuration.supplementaryEvery = 1_000
        let session = OBDSession(transport: transport, configuration: configuration)
        _ = try await session.initialize()
        transport.handler = { _ in .silent }
        // Ab hier kurze Zeitlimits – es kommt ohnehin keine Antwort.
        session.configuration.commandTimeout = .milliseconds(200)

        let first = try await session.pollOnce()
        #expect(first.rpm == nil)
        #expect(first.rpmTimedOut)
        _ = try await session.pollOnce()
        await #expect(throws: OBDSessionError.linkLost("Der Adapter antwortet nicht mehr.")) {
            _ = try await session.pollOnce()
        }
    }

    @Test func lateResponseAfterTimeoutIsNotMisattributed() async throws {
        let transport = MockELMTransport()
        var configuration = fastConfiguration()
        configuration.drainDuration = .milliseconds(1_500)
        let session = OBDSession(transport: transport, configuration: configuration)
        _ = try await session.initialize()

        let healthy = MockELMTransport.healthyCar(rpmHex: "0B 20")
        session.configuration.commandTimeout = .milliseconds(200)
        transport.handler = { command in
            // Antwort kommt deutlich nach dem Zeitlimit (200 ms), aber innerhalb der Verwerfphase.
            command == "010C" ? .respond("7E8 04 41 0C 3E 80\r\r>", delay: .milliseconds(700)) : healthy(command)
        }
        let late = try await session.pollOnce()
        #expect(late.rpm == nil)
        #expect(late.rpmTimedOut)

        transport.handler = healthy
        session.configuration.commandTimeout = .seconds(2)
        let next = try await session.pollOnce()
        #expect(next.rpm == 712)
    }

    @Test func commandsAreStrictlySerialized() async throws {
        let transport = MockELMTransport()
        transport.handler = MockELMTransport.healthyCar(rpmHex: "1A F8", chunks: 3)
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        _ = try await session.initialize()

        async let a = session.send("010C", timeout: .seconds(1))
        async let b = session.send("010D", timeout: .seconds(1))
        async let c = session.send("0104", timeout: .seconds(1))
        let replies = try await [a, b, c]
        #expect(!transport.overlappingRequestDetected)
        #expect(Set(replies.map(\.command)) == ["010C", "010D", "0104"])
        for reply in replies {
            let expectedPID: OBDPID = switch reply.command {
            case "010C": .engineRPM
            case "010D": .vehicleSpeed
            default: .engineLoad
            }
            #expect(!OBDResponseDecoder.frames(for: expectedPID, in: reply.lines).isEmpty)
        }
    }

    @Test func multipleECUsUseConsistentSource() async throws {
        let transport = MockELMTransport()
        let healthy = MockELMTransport.healthyCar(rpmHex: "1A F8")
        var order = 0
        transport.handler = { command in
            guard command == "010C" else { return healthy(command) }
            order += 1
            // Reihenfolge der Antworten wechselt; 7E9 meldet einen anderen Wert.
            return order % 2 == 0
                ? .respond("7E9 04 41 0C 0B 20\r7E8 04 41 0C 1A F8\r\r>")
                : .respond("7E8 04 41 0C 1A F8\r7E9 04 41 0C 0B 20\r\r>")
        }
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        _ = try await session.initialize()
        for _ in 0..<4 {
            let result = try await session.pollOnce()
            #expect(result.rpm == 1_726)
        }
        #expect(session.lockedECU == "7E8")
    }

    @Test func adapterResetForcesReconnect() async throws {
        let transport = MockELMTransport()
        let healthy = MockELMTransport.healthyCar(rpmHex: "1A F8")
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        _ = try await session.initialize()
        transport.handler = { command in
            command == "010C" ? .respond("LV RESET\r\r>") : healthy(command)
        }
        await #expect(throws: OBDSessionError.self) {
            _ = try await session.pollOnce()
        }
    }

    @Test func closingFailsPendingCommand() async throws {
        let transport = MockELMTransport()
        transport.handler = { _ in .silent }
        let session = OBDSession(transport: transport, configuration: fastConfiguration())
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            session.close(reason: .linkLost("weg"))
        }
        await #expect(throws: OBDSessionError.linkLost("weg")) {
            _ = try await session.send("010C", timeout: .seconds(2))
        }
        // Spätere Befehle melden denselben Grund (wichtig für die Wiederverbindung).
        await #expect(throws: OBDSessionError.linkLost("weg")) {
            _ = try await session.send("010C", timeout: .seconds(2))
        }
    }
}
