//
//  PendingOperation.swift
//  DemonicRevAwakening OBD2
//
//  Brücke zwischen Callback-APIs (CoreBluetooth, Network, ELM327-Strom)
//  und async/await – mit Zeitlimit. Läuft auf dem MainActor.
//

import Foundation

final class PendingOperation<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutTask: Task<Void, Never>?

    var isPending: Bool { continuation != nil }

    /// Startet die Operation über `start` und wartet höchstens `timeout`.
    /// `start` wird synchron aufgerufen, nachdem die Fortsetzung registriert ist.
    /// `timeoutError` wird erst beim Ablauf ausgewertet und kann so den
    /// zuletzt bekannten Grund beschreiben.
    func run(timeout: Duration, timeoutError: @escaping @autoclosure () -> Error, start: () -> Void) async throws -> Value {
        if continuation != nil {
            fail(CancellationError())
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.fail(timeoutError())
            }
            start()
        }
    }

    func succeed(_ value: Value) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: value)
    }

    func fail(_ error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(throwing: error)
    }
}
