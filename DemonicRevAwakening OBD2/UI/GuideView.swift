//
//  GuideView.swift
//  DemonicRevAwakening OBD2
//
//  Bereich „Anleitung“.
//

import SwiftUI

struct GuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let thresholds = model.settings.settings.thresholds
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    safetyNote

                    GuideCard(title: "Die Zustände des Dämons", icon: "flame.fill") {
                        stateRow(.disconnected, "Keine Verbindung und keine Demo. Der Dämon wartet neutral, die Hörner glimmen nur schwach.")
                        stateRow(.waitingForData, "Verbunden, aber es liegt keine aktuelle Drehzahl vor. Es wird keine Drehzahl erfunden.")
                        stateRow(.engineOff, "Das Fahrzeug meldet gültig 0 RPM: tiefer Schlaf, kaum Aura.")
                        stateRow(.idle, "Leerlauf bis \(format(thresholds.awakeningStart)) RPM: Augen geschlossen, langsamer Atem, gelegentliche kleine Bewegungen.")
                        stateRow(.awakening, "\(format(thresholds.awakeningStart))–\(format(thresholds.awakeStart)) RPM: die Augen öffnen sich schrittweise, der Kopf hebt sich, erstes grünes Leuchten.")
                        stateRow(.awake, "\(format(thresholds.awakeStart))–\(format(thresholds.unleashedStart)) RPM: offene, leuchtende Augen, sichtbare Aura.")
                        stateRow(.unleashed, "Ab \(format(thresholds.unleashedStart)) RPM: starkes Leuchten, mehr Energiepartikel, grimmiger Ausdruck.")
                        paragraph("Die Energie wächst zusätzlich stufenlos mit der Drehzahl. Hysterese und Glättung verhindern ständiges Umspringen an den Schwellen. Ein schneller Drehzahlanstieg löst eine kurze Reaktion aus – die App erkennt daraus keinen Gangwechsel. Alle Schwellen sind reine Animationswerte und in den Einstellungen anpassbar.")
                    }

                    GuideCard(title: "Bluetooth-LE-Adapter verbinden", icon: "dot.radiowaves.left.and.right") {
                        numbered(1, "Adapter im Stand in die OBD2-Buchse stecken (meist auf der Fahrerseite unterhalb des Armaturenbretts) und die Zündung einschalten.")
                        numbered(2, "In der App „Verbinden“ › „Bluetooth LE“ › „Nach Adaptern suchen“ wählen und den Bluetooth-Zugriff erlauben.")
                        numbered(3, "Den Adapter auswählen und das passende Profil bestätigen. Nicht über die iOS-Bluetooth-Einstellungen koppeln – die Verbindung baut die App selbst auf.")
                        numbered(4, "Die App prüft Dienst und Characteristics. Passt das Profil nicht, erscheint eine verständliche Meldung.")
                        paragraph("Mitgeliefert ist das dokumentierte Profil für den OBDLink CX. Für andere BLE-Adapter kannst du unter Einstellungen › Erweitert ein eigenes Profil mit den UUIDs aus der Herstellerdokumentation eintragen.")
                    }

                    GuideCard(title: "WLAN-Adapter verbinden", icon: "wifi") {
                        numbered(1, "Adapter einstecken, Zündung einschalten.")
                        numbered(2, "In den iOS-Einstellungen das WLAN des Adapters auswählen. Es hat meist keinen Internetzugang – das ist normal.")
                        numbered(3, "In der App „Verbinden“ › „WLAN“ IP-Adresse und Port eintragen (häufig 192.168.0.10 und 35000, maßgeblich ist die Anleitung des Adapters).")
                        numbered(4, "Den Zugriff auf das lokale Netzwerk erlauben, wenn iOS danach fragt.")
                    }

                    GuideCard(title: "Grenzen von iOS und Adaptern", icon: "exclamationmark.shield") {
                        paragraph("iOS-Apps können nur mit Bluetooth-LE-Adaptern oder per WLAN kommunizieren. Klassische Bluetooth-Adapter (SPP, oft „Bluetooth 2.0“ oder „nur Android“) funktionieren mit iOS-Apps in der Regel nicht. Adapter, die nur über Apples MFi-Programm (External Accessory) arbeiten, werden von dieser App nicht unterstützt.")
                        paragraph("Nicht jedes Gerät in der Bluetooth-Suche ist ein OBD2-Adapter. Unbekannte Geräte werden als „nicht konfiguriert“ angezeigt.")
                        paragraph("Im Hintergrund trennt die App die Verbindung und setzt sie beim Zurückkehren fort. Eine dauerhafte Hintergrundverbindung gibt es bewusst nicht.")
                    }

                    GuideCard(title: "Demo-Modus", icon: "theatermasks.fill") {
                        paragraph("Ohne Adapter – auch im Simulator – zeigt die Demo den kompletten Ablauf: Motorstart, Leerlauf, Gasstoß, Drehzahlanstieg und Beruhigung. Im manuellen Modus stellst du die Drehzahl per Schieberegler zwischen 0 und 8.000 RPM ein. Pausieren und Neustart sind jederzeit möglich.")
                        paragraph("Solange die Demo läuft, ist „Demo – simulierte Fahrzeugdaten“ sichtbar. Bricht eine Live-Verbindung ab, wechselt die App niemals automatisch in die Demo.")
                    }

                    GuideCard(title: "Welche Daten verfügbar sind", icon: "car.fill") {
                        paragraph("Die App liest ausschließlich: Motordrehzahl (PID 0C) mit Vorrang sowie – sofern Fahrzeug und Adapter sie melden – Geschwindigkeit, berechnete Motorlast und Drosselklappenstellung. Die Drosselklappenstellung ist nicht dasselbe wie die Gaspedalstellung.")
                        paragraph("Vorgesehen ist ein Honda Jazz von 2015. Welche Werte tatsächlich verfügbar sind, hängt von Fahrzeug und Adapter ab und ist erst nach einem echten Test bestätigt. Die App löscht keine Fehlercodes, codiert nichts und steuert keine Fahrzeugfunktionen.")
                    }

                    GuideCard(title: "Fehlerhilfe", icon: "wrench.and.screwdriver") {
                        help("„Wartet auf Daten“ / NO DATA", "Zündung einschalten bzw. Motor starten. Manche Fahrzeuge antworten erst einige Sekunden nach dem Einschalten.")
                        help("UNABLE TO CONNECT", "Der Adapter findet kein OBD-Protokoll. Zündung prüfen, Adapter fest einstecken, erneut verbinden.")
                        help("Adapter antwortet nicht", "Adapter aus- und wieder einstecken. Bei BLE: Ist das richtige Profil gewählt? Bei WLAN: Ist das iPhone mit dem Adapter-WLAN verbunden?")
                        help("„Veraltet“ neben der Drehzahl", "Seit über 2,5 Sekunden kam kein gültiger Wert. Der Dämon wartet, statt einen alten Wert weiter anzuzeigen.")
                        help("Verbindungsabbruch", "Die App versucht es mit wachsenden Abständen erneut (abschaltbar). Mit „Wiederverbindung abbrechen“ stoppst du die Versuche.")
                        help("Lokales Netzwerk verweigert", "iOS-Einstellungen › Datenschutz & Sicherheit › Lokales Netzwerk › Demonic RevAwakening aktivieren.")
                    }
                }
                .padding(20)
            }
            .background(BackgroundGradient())
            .navigationTitle("Anleitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private var safetyNote: some View {
        Label {
            Text("Einrichtung nur im Stand. Während der Fahrt die App nicht bedienen – der Blick gehört auf die Straße.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Theme.warning)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 18)
    }

    private func format(_ rpm: Double) -> String {
        RPMReadout.rpmText(rpm, freshness: .fresh)
    }

    private func stateRow(_ mood: DemonMood, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mood.title)
                .font(.headline)
                .foregroundStyle(Theme.color(for: mood) == Theme.textTertiary ? Theme.textSecondary : Theme.color(for: mood))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.green)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func help(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GuideCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 20)
    }
}
