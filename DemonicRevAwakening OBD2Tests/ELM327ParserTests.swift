//
//  ELM327ParserTests.swift
//  DemonicRevAwakening OBD2Tests
//

import Foundation
import Testing
@testable import DemonicRevAwakening_OBD2

struct ELM327AssemblerTests {
    @Test func buffersFragmentsUntilPrompt() {
        var assembler = ELM327ResponseAssembler()
        #expect(assembler.append(Data("41 0C ".utf8)).isEmpty)
        #expect(assembler.append(Data("1A F8\r".utf8)).isEmpty)
        #expect(assembler.hasPendingData)
        let responses = assembler.append(Data("\r>".utf8))
        #expect(responses == ["41 0C 1A F8\r\r"])
        #expect(!assembler.hasPendingData)
    }

    @Test func splitsMultipleResponsesInOneChunk() {
        var assembler = ELM327ResponseAssembler()
        let responses = assembler.append(Data("OK\r\r>OK\r\r>41 0D".utf8))
        #expect(responses.count == 2)
        #expect(assembler.hasPendingData)
    }

    @Test func dropsNullAndNonASCIIBytes() {
        var assembler = ELM327ResponseAssembler()
        var bytes = Array("41 0C 0B".utf8)
        bytes.insert(0x00, at: 2)
        bytes.append(0xFF)
        bytes += Array(" 20\r>".utf8)
        let responses = assembler.append(Data(bytes))
        #expect(responses == ["41 0C 0B 20\r"])
    }

    @Test func limitsBufferGrowth() {
        var assembler = ELM327ResponseAssembler()
        _ = assembler.append(Data(String(repeating: "A", count: 20_000).utf8))
        let responses = assembler.append(Data(">".utf8))
        #expect(responses.first?.count == ELM327ResponseAssembler.maximumBufferLength)
    }
}

struct ELM327ReplyParserTests {
    @Test func removesEchoAndEmptyLines() {
        let reply = ELM327ReplyParser.parse("010C\r41 0C 1A F8\r\r", command: "010C")
        #expect(reply.lines == ["41 0C 1A F8"])
        #expect(reply.status == nil)
        #expect(reply.isOK)
    }

    @Test func removesEchoWithDifferentSpacing() {
        let reply = ELM327ReplyParser.parse("01 0c\n\n41 0C 1A F8\n", command: "010C")
        #expect(reply.lines == ["41 0C 1A F8"])
    }

    @Test func skipsSearchingAndBusInit() {
        let reply = ELM327ReplyParser.parse("SEARCHING...\rBUS INIT: ...OK\r41 00 BE 1F A8 13\r", command: "0100")
        #expect(reply.didSearch)
        #expect(reply.lines == ["41 00 BE 1F A8 13"])
        #expect(reply.status == nil)
    }

    @Test(arguments: [
        ("NO DATA", ELM327Status.noData),
        ("STOPPED", .stopped),
        ("UNABLE TO CONNECT", .unableToConnect),
        ("CAN ERROR", .canError),
        ("BUS BUSY", .busBusy),
        ("BUS ERROR", .busError),
        ("FB ERROR", .busError),
        ("BUFFER FULL", .bufferFull),
        ("?", .unknownCommand),
        ("LV RESET", .adapterReset),
        ("ACT ALERT", .adapterReset),
    ])
    func recognizesStatusMessages(text: String, expected: ELM327Status) {
        let reply = ELM327ReplyParser.parse("\(text)\r\r", command: "010C")
        #expect(reply.status == expected)
        #expect(reply.lines.isEmpty)
        #expect(!reply.isOK)
    }

    @Test func searchingFollowedByUnableToConnect() {
        let reply = ELM327ReplyParser.parse("SEARCHING...\rUNABLE TO CONNECT\r", command: "0100")
        #expect(reply.didSearch)
        #expect(reply.status == .unableToConnect)
    }

    @Test func busInitErrorIsReported() {
        let reply = ELM327ReplyParser.parse("BUS INIT: ...ERROR\r", command: "0100")
        #expect(reply.status == .busInitError)
    }

    @Test func dataErrorLinesAreDropped() {
        let reply = ELM327ReplyParser.parse("41 0C 1A F8 <DATA ERROR\r", command: "010C")
        #expect(reply.lines.isEmpty)
        #expect(reply.status == .dataError)
    }

    @Test func okIsStatusOK() {
        let reply = ELM327ReplyParser.parse("ATE0\rOK\r\r", command: "ATE0")
        #expect(reply.status == .ok)
        #expect(reply.isOK)
    }

    @Test func keepsAdapterIdentityAsLine() {
        let reply = ELM327ReplyParser.parse("\r\rELM327 v1.5\r\r", command: "ATZ")
        #expect(reply.lines == ["ELM327 v1.5"])
    }
}
