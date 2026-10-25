//
//  OBDPID.swift
//  DemonicRevAwakening OBD2
//
//  Mode-01-PIDs (SAE J1979) und Dekodierung der Antwortrahmen.
//  Ausschließlich lesende Abfragen.
//

import Foundation

nonisolated enum OBDPID: UInt8, CaseIterable, Sendable {
    case supported01To20 = 0x00
    case engineLoad = 0x04
    case engineRPM = 0x0C
    case vehicleSpeed = 0x0D
    case throttlePosition = 0x11

    static let mode: UInt8 = 0x01

    /// Anzahl der Datenbytes (A, B, …) nach Mode und PID.
    var dataByteCount: Int {
        switch self {
        case .supported01To20: 4
        case .engineRPM: 2
        case .engineLoad, .vehicleSpeed, .throttlePosition: 1
        }
    }

    /// ELM327-Befehl, z. B. „010C“.
    var command: String {
        "01" + Self.hex(rawValue)
    }

    var title: String {
        switch self {
        case .supported01To20: "Unterstützte PIDs 01–20"
        case .engineLoad: "Berechnete Motorlast"
        case .engineRPM: "Motordrehzahl"
        case .vehicleSpeed: "Geschwindigkeit"
        case .throttlePosition: "Drosselklappenstellung"
        }
    }

    /// Dekodiert die Datenbytes in einen physikalischen Wert.
    func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= dataByteCount else { return nil }
        switch self {
        case .supported01To20:
            return nil
        case .engineRPM:
            // ((A * 256) + B) / 4
            return (Double(bytes[0]) * 256 + Double(bytes[1])) / 4
        case .vehicleSpeed:
            return Double(bytes[0])
        case .engineLoad, .throttlePosition:
            return Double(bytes[0]) * 100 / 255
        }
    }

    static func hex(_ byte: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
    }
}

/// Datenbytes eines Steuergeräts für eine Mode-01-Antwort.
nonisolated struct OBDFrame: Equatable, Sendable {
    /// Kennung des antwortenden Steuergeräts (Header), leer ohne Header.
    var ecu: String
    /// Datenbytes nach Mode und PID.
    var data: [UInt8]
}

nonisolated enum OBDResponseDecoder {
    /// Sucht in den Datenzeilen alle Antworten auf `pid` und liefert pro
    /// Zeile einen Rahmen. Unterstützt Antworten mit und ohne Leerzeichen
    /// sowie mit Headern (CAN 11/29 Bit, ältere Protokolle).
    static func frames(for pid: OBDPID, in lines: [String]) -> [OBDFrame] {
        frames(mode: OBDPID.mode, pid: pid.rawValue, dataBytes: pid.dataByteCount, in: lines)
    }

    static func frames(mode: UInt8, pid: UInt8, dataBytes: Int, in lines: [String]) -> [OBDFrame] {
        lines.compactMap { line in
            guard let (header, bytes) = tokenize(line) else { return nil }
            let marker = 0x40 + mode
            var index = 0
            while index + 1 < bytes.count {
                if bytes[index] == marker, bytes[index + 1] == pid, bytes.count >= index + 2 + dataBytes {
                    if header != nil, index > 0, !pciAllows(bytes[index - 1], dataBytes: dataBytes) {
                        index += 1
                        continue
                    }
                    let data = Array(bytes[(index + 2)..<(index + 2 + dataBytes)])
                    let ecu = header ?? ecuIdentifier(from: Array(bytes[..<index]))
                    return OBDFrame(ecu: ecu, data: data)
                }
                index += 1
            }
            return nil
        }
    }

    /// Bitmaske von PID 00/20/40… in eine Menge unterstützter PIDs umwandeln.
    static func supportedPIDs(base: UInt8, bitmask: [UInt8]) -> Set<UInt8> {
        var result = Set<UInt8>()
        for (byteIndex, byte) in bitmask.prefix(4).enumerated() {
            for bit in 0..<8 where byte & (0x80 >> UInt8(bit)) != 0 {
                result.insert(base &+ UInt8(byteIndex * 8 + bit + 1))
            }
        }
        return result
    }

    // MARK: - Hilfsfunktionen

    /// Zerlegt eine Zeile in Bytes. Ein führender 3-stelliger CAN-11-Bit-Header
    /// (z. B. „7E8“) wird separat zurückgegeben.
    static func tokenize(_ line: String) -> (header: String?, bytes: [UInt8])? {
        let trimmed = line.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return nil }
        var header: String?
        var hexBody: String

        if trimmed.contains(" ") {
            var tokens = trimmed.split(separator: " ").map(String.init)
            if let first = tokens.first, first.count == 3, isHex(first) {
                header = first
                tokens.removeFirst()
            }
            guard tokens.allSatisfy({ $0.count == 2 && isHex($0) }) else { return nil }
            hexBody = tokens.joined()
        } else {
            guard isHex(trimmed) else { return nil }
            hexBody = trimmed
            if trimmed.count % 2 == 1 {
                // Ungerade Länge ohne Leerzeichen: 11-Bit-Header vorangestellt.
                guard trimmed.count > 3 else { return nil }
                header = String(trimmed.prefix(3))
                hexBody = String(trimmed.dropFirst(3))
            }
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexBody.count / 2)
        var index = hexBody.startIndex
        while index < hexBody.endIndex {
            let next = hexBody.index(index, offsetBy: 2)
            guard let byte = UInt8(hexBody[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return (header, bytes)
    }

    /// Prüft bei CAN-Antworten mit Header, ob das PCI-Byte (Single Frame)
    /// zur erwarteten Länge passt.
    private static func pciAllows(_ pci: UInt8, dataBytes: Int) -> Bool {
        let frameType = pci >> 4
        let length = Int(pci & 0x0F)
        return frameType == 0 && length >= 2 + dataBytes
    }

    private static func ecuIdentifier(from headerBytes: [UInt8]) -> String {
        // Bei CAN 29 Bit folgt auf vier Header-Bytes noch das PCI-Byte.
        let relevant = headerBytes.count >= 5 ? Array(headerBytes.prefix(4)) : headerBytes
        return relevant.map(OBDPID.hex).joined()
    }

    private static func isHex(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isHexDigit)
    }
}
