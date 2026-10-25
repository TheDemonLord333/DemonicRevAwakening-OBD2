//
//  OBDDecodingTests.swift
//  DemonicRevAwakening OBD2Tests
//

import Foundation
import Testing
@testable import DemonicRevAwakening_OBD2

struct OBDPIDTests {
    @Test func rpmFormula() {
        // ((A * 256) + B) / 4
        #expect(OBDPID.engineRPM.decode([0x1A, 0xF8]) == 1_726)
        #expect(OBDPID.engineRPM.decode([0x00, 0x00]) == 0)
        #expect(OBDPID.engineRPM.decode([0x0B, 0x20]) == 712)
        #expect(OBDPID.engineRPM.decode([0xFF, 0xFF]) == 16_383.75)
        #expect(OBDPID.engineRPM.decode([0x1A]) == nil)
    }

    @Test func supplementaryFormulas() {
        #expect(OBDPID.vehicleSpeed.decode([0x32]) == 50)
        #expect(OBDPID.engineLoad.decode([0xFF]) == 100)
        #expect(OBDPID.throttlePosition.decode([0x00]) == 0)
    }

    @Test func commands() {
        #expect(OBDPID.engineRPM.command == "010C")
        #expect(OBDPID.supported01To20.command == "0100")
        #expect(OBDPID.throttlePosition.command == "0111")
    }
}

struct OBDResponseDecoderTests {
    @Test(arguments: [
        "41 0C 1A F8",          // Header aus, Leerzeichen an
        "410C1AF8",             // Header aus, Leerzeichen aus
        "7E8 04 41 0C 1A F8 AA AA AA", // CAN 11 Bit mit Header und Padding
        "7E804410C1AF8",        // CAN 11 Bit ohne Leerzeichen
        "18 DA F1 10 04 41 0C 1A F8", // CAN 29 Bit
        "48 6B 10 41 0C 1A F8 C3",    // ältere Protokolle mit Prüfsumme
    ])
    func decodesRPMInAllFormats(line: String) {
        let frames = OBDResponseDecoder.frames(for: .engineRPM, in: [line])
        #expect(frames.count == 1)
        #expect(frames.first.flatMap { OBDPID.engineRPM.decode($0.data) } == 1_726)
    }

    @Test func identifiesECUs() {
        let lines = ["7E9 04 41 0C 0B 20", "7E8 04 41 0C 1A F8"]
        let frames = OBDResponseDecoder.frames(for: .engineRPM, in: lines)
        #expect(frames.map(\.ecu) == ["7E9", "7E8"])
        let can29 = OBDResponseDecoder.frames(for: .engineRPM, in: ["18 DA F1 10 04 41 0C 1A F8"])
        #expect(can29.first?.ecu == "18DAF110")
    }

    @Test func rejectsTruncatedAndForeignResponses() {
        #expect(OBDResponseDecoder.frames(for: .engineRPM, in: ["41 0C 1A"]).isEmpty)
        #expect(OBDResponseDecoder.frames(for: .engineRPM, in: ["41 0D 32"]).isEmpty)
        #expect(OBDResponseDecoder.frames(for: .engineRPM, in: ["7E8 03 41 0C 1A F8"]).isEmpty) // PCI zu kurz
        #expect(OBDResponseDecoder.frames(for: .engineRPM, in: ["GARBAGE"]).isEmpty)
        #expect(OBDResponseDecoder.frames(for: .engineRPM, in: ["0: 41 0C 1A F8"]).isEmpty)
        #expect(OBDResponseDecoder.frames(for: .engineRPM, in: ["4X 0C 1A F8"]).isEmpty)
    }

    @Test func supportedPIDBitmask() {
        // Beispiel aus SAE J1979 / Wikipedia: 41 00 BE 1F A8 13
        let supported = OBDResponseDecoder.supportedPIDs(base: 0x00, bitmask: [0xBE, 0x1F, 0xA8, 0x13])
        #expect(supported == [0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
                              0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20])
        #expect(supported.contains(OBDPID.engineRPM.rawValue))
    }

    @Test func unsupportedPIDsAreAbsent() {
        // Nur PID 01 und 0D unterstützt – keine Drehzahl.
        let supported = OBDResponseDecoder.supportedPIDs(base: 0x00, bitmask: [0x80, 0x08, 0x00, 0x00])
        #expect(supported == [0x01, 0x0D])
        #expect(!supported.contains(OBDPID.engineRPM.rawValue))
    }
}
