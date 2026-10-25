//
//  VehicleData.swift
//  DemonicRevAwakening OBD2
//

import Foundation

/// Ein Messwert mit Empfangszeitpunkt.
nonisolated struct TimedValue: Equatable, Sendable {
    var value: Double
    var timestamp: Date

    func age(at now: Date) -> TimeInterval { now.timeIntervalSince(timestamp) }
}

/// Herkunft der angezeigten Daten. Demo-Daten werden immer als solche markiert.
nonisolated enum DataOrigin: Equatable, Sendable {
    case live
    case demo
}

/// Aktueller Stand aller bekannten Fahrzeugwerte.
nonisolated struct VehicleSnapshot: Equatable, Sendable {
    var origin: DataOrigin
    var rpm: TimedValue?
    var speedKmh: TimedValue?
    var engineLoadPercent: TimedValue?
    /// Drosselklappenstellung (PID 11) – nicht gleichbedeutend mit der Gaspedalstellung.
    var throttlePercent: TimedValue?

    init(origin: DataOrigin,
         rpm: TimedValue? = nil,
         speedKmh: TimedValue? = nil,
         engineLoadPercent: TimedValue? = nil,
         throttlePercent: TimedValue? = nil) {
        self.origin = origin
        self.rpm = rpm
        self.speedKmh = speedKmh
        self.engineLoadPercent = engineLoadPercent
        self.throttlePercent = throttlePercent
    }
}

/// Bewertung, ob ein Wert noch aktuell ist.
nonisolated enum Freshness: Equatable, Sendable {
    case missing
    case fresh
    case stale(age: TimeInterval)

    init(_ value: TimedValue?, now: Date, maxAge: TimeInterval) {
        guard let value else { self = .missing; return }
        let age = value.age(at: now)
        self = age <= maxAge ? .fresh : .stale(age: age)
    }

    var isFresh: Bool { self == .fresh }
}

/// Eingabe für die Dämonen-Logik. Es gibt bewusst keinen Fall, der eine
/// Drehzahl ohne gültigen Messwert erfindet.
nonisolated enum DemonInput: Equatable, Sendable {
    /// Weder Live-Verbindung noch Demo aktiv.
    case noConnection
    /// Verbunden, aber keine aktuelle, gültige Drehzahl vorhanden.
    case awaitingData
    /// Gültige, aktuelle Drehzahl.
    case rpm(Double)
}

nonisolated enum DemonInputResolver {
    /// Standard-Höchstalter einer Drehzahl, bevor sie als veraltet gilt.
    static let defaultMaxAge: TimeInterval = 2.5

    static func resolve(isDataPathActive: Bool,
                        snapshot: VehicleSnapshot?,
                        now: Date,
                        maxAge: TimeInterval = defaultMaxAge) -> DemonInput {
        guard isDataPathActive else { return .noConnection }
        guard let rpm = snapshot?.rpm,
              Freshness(rpm, now: now, maxAge: maxAge).isFresh,
              rpm.value.isFinite, rpm.value >= 0 else {
            return .awaitingData
        }
        return .rpm(rpm.value)
    }
}
