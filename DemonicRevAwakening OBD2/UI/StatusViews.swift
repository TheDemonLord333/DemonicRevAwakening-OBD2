//
//  StatusViews.swift
//  DemonicRevAwakening OBD2
//
//  Verbindungsstatus, Drehzahlanzeige, Zusatzwerte und Demo-Kennzeichnung.
//

import SwiftUI

private let germanLocale = Locale(identifier: "de_DE")

/// Kompakte Anzeige des Verbindungszustands.
struct ConnectionStatusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = Self.status(for: model.connection)
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .shadow(color: status.color.opacity(0.8), radius: 4)
            Text(status.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verbindungsstatus: \(status.text)")
    }

    struct Status {
        var text: String
        var color: Color
    }

    static func status(for connection: VehicleConnectionController) -> Status {
        switch connection.mode {
        case .none:
            return Status(text: "Nicht verbunden", color: Theme.textTertiary)
        case .demo:
            return Status(text: "Demo aktiv", color: Theme.violet)
        case .live:
            let name = connection.target?.displayName ?? "Adapter"
            switch connection.linkState {
            case .idle:
                return Status(text: "Nicht verbunden", color: Theme.textTertiary)
            case .connecting:
                return Status(text: "Verbinde mit \(name) …", color: Theme.warning)
            case .initializing:
                return Status(text: "Initialisiere Adapter …", color: Theme.warning)
            case .streaming:
                if let rate = connection.pollingRateHz {
                    let formatted = rate.formatted(.number.precision(.fractionLength(0)).locale(germanLocale))
                    return Status(text: "Live · \(name) · \(formatted) Hz", color: Theme.green)
                }
                return Status(text: "Live · \(name)", color: Theme.green)
            case .reconnecting(let attempt, let maxAttempts, _):
                return Status(text: "Verbindung verloren – Versuch \(attempt)/\(maxAttempts)", color: Theme.warning)
            case .suspended:
                return Status(text: "Pausiert (App im Hintergrund)", color: Theme.textTertiary)
            case .failed:
                return Status(text: "Verbindung fehlgeschlagen", color: Theme.danger)
            }
        }
    }
}

/// Adapterkennung und Protokoll einer Live-Verbindung (hilfreich beim Hardwaretest).
struct AdapterInfoLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.connection.mode == .live, let info = model.connection.adapterInfo {
            let parts = [info.identity, info.protocolName].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Adapter: \(parts.joined(separator: ", "))")
            }
        }
    }
}

/// Deutlich sichtbare Kennzeichnung des Demo-Modus.
struct DemoBadge: View {
    var body: some View {
        Label("Demo – simulierte Fahrzeugdaten", systemImage: "theatermasks.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.violet.opacity(0.85)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Theme.violet.opacity(0.6), radius: 8)
            .accessibilityLabel("Demo-Modus aktiv: simulierte Fahrzeugdaten")
    }
}

/// Große Drehzahl und Zustandstext des Dämons.
struct RPMReadout: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        // Zeitabhängige Bewertung (veraltet) ohne Dauer-Neuzeichnen: 2 Hz genügen.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            content
        }
    }

    private var content: some View {
        let connection = model.connection
        let frame = model.presentation.frame
        let freshness = connection.rpmFreshness()
        let rpmValue = connection.snapshot?.rpm?.value

        return VStack(spacing: compact ? 2 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.rpmText(rpmValue, freshness: freshness))
                    .font(.system(size: compact ? 44 : 64, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(freshness.isFresh ? Theme.textPrimary : Theme.textTertiary)
                    .shadow(color: Theme.color(for: frame.mood).opacity(freshness.isFresh ? 0.6 : 0), radius: 12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("RPM")
                    .font(.system(size: compact ? 16 : 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(frame.mood.title)
                .font(.system(size: compact ? 20 : 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.color(for: frame.mood))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: frame.mood)
            if !compact || !freshness.isFresh {
                Text(detailText(freshness: freshness, mood: frame.mood))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(rpm: rpmValue, freshness: freshness, mood: frame.mood))
    }

    static func rpmText(_ rpm: Double?, freshness: Freshness) -> String {
        guard let rpm else { return "–" }
        let rounded = (rpm / 10).rounded() * 10
        return rounded.formatted(.number.precision(.fractionLength(0)).grouping(.automatic).locale(germanLocale))
    }

    private func detailText(freshness: Freshness, mood: DemonMood) -> String {
        let connection = model.connection
        if case .stale(let age) = freshness, connection.isDataPathActive {
            let seconds = age.formatted(.number.precision(.fractionLength(0)).locale(germanLocale))
            return "Veraltet – letzter gültiger Wert vor \(seconds) s"
        }
        if connection.mode == .live, connection.linkState == .streaming, let status = connection.lastRPMStatus,
           !freshness.isFresh {
            return "Adapter meldet: \(status.description)"
        }
        return mood.detail
    }

    private func accessibilityText(rpm: Double?, freshness: Freshness, mood: DemonMood) -> String {
        var parts = ["Dämon: \(mood.title)"]
        if let rpm {
            parts.append("\(Self.rpmText(rpm, freshness: freshness)) Umdrehungen pro Minute")
            if !freshness.isFresh { parts.append("Wert veraltet") }
        } else {
            parts.append("keine Drehzahl verfügbar")
        }
        if model.connection.mode == .demo { parts.append("Demo-Daten") }
        return parts.joined(separator: ", ")
    }
}

/// Kleine Zusatzwerte – nur wenn verfügbar.
struct MetricsRow: View {
    @Environment(AppModel.self) private var model

    private struct Metric: Identifiable {
        let id: String
        let icon: String
        let value: TimedValue?
        let unit: String
    }

    var body: some View {
        let snapshot = model.connection.snapshot
        let now = Date()
        let maxAge = model.connection.staleAfter * 2
        let metrics = [
            Metric(id: "Geschwindigkeit", icon: "speedometer", value: snapshot?.speedKmh, unit: "km/h"),
            Metric(id: "Motorlast", icon: "gauge.with.dots.needle.33percent", value: snapshot?.engineLoadPercent, unit: "%"),
            Metric(id: "Drosselklappe", icon: "dial.medium", value: snapshot?.throttlePercent, unit: "%"),
        ].filter { $0.value != nil }

        if !metrics.isEmpty {
            HStack(spacing: 10) {
                ForEach(metrics) { metric in
                    let isFresh = Freshness(metric.value, now: now, maxAge: maxAge).isFresh
                    VStack(spacing: 2) {
                        Image(systemName: metric.icon)
                            .font(.caption)
                            .foregroundStyle(Theme.blurple)
                        Text(Self.format(metric.value?.value) + " " + metric.unit)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(isFresh ? Theme.textPrimary : Theme.textTertiary)
                        Text(metric.id)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassPanel(cornerRadius: 14)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(metric.id): \(Self.format(metric.value?.value)) \(metric.unit)\(isFresh ? "" : ", veraltet")")
                }
            }
        }
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0)).locale(germanLocale))
    }
}

/// Hinweis bei Fehlern und laufender Wiederverbindung mit passenden Aktionen.
struct ConnectionAlertBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let connection = model.connection
        switch connection.linkState {
        case .reconnecting(_, _, let retryAt):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(retryAt.timeIntervalSince(context.date).rounded(.up)))
                banner(icon: "arrow.triangle.2.circlepath",
                       title: "Verbindung unterbrochen",
                       message: (connection.lastError.map { $0 + " " } ?? "")
                           + (seconds > 0 ? "Neuer Versuch in \(seconds) s." : "Verbinde erneut …"),
                       color: Theme.warning) {
                    Button("Wiederverbindung abbrechen") { connection.cancelReconnect() }
                        .buttonStyle(DemonButtonStyle(kind: .secondary))
                }
            }
        case .failed(let message):
            banner(icon: "exclamationmark.triangle.fill", title: "Keine Verbindung", message: message,
                   color: Theme.danger) {
                HStack(spacing: 10) {
                    Button("Erneut versuchen") { connection.retry() }
                        .buttonStyle(DemonButtonStyle(kind: .secondary))
                    Button("Schließen") { connection.disconnect() }
                        .buttonStyle(DemonButtonStyle(kind: .secondary))
                }
            }
        default:
            EmptyView()
        }
    }

    private func banner(icon: String, title: String, message: String, color: Color,
                        @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 18)
    }
}
