# Demonic RevAwakening

Native iOS-App (Swift, SwiftUI, SpriteKit): ein animierter dämonischer Begleiter,
der mit der **echten Motordrehzahl** deines Autos erwacht. Die Drehzahl liest die App
über einen OBD2-Adapter (Bluetooth LE oder WLAN). Im Leerlauf schläft der Dämon. Mit
steigender Drehzahl öffnet er die Augen, die Augen glühen neongrün, die Hörner leuchten
blau-violett und eine Energieaura wächst.

- Anzeigename: **Demonic RevAwakening**
- Bundle-ID: `me.thedemonlord333.DemonicRevAwakening-OBD2`
- Swift-Modul: `DemonicRevAwakening_OBD2`
- Deployment Target: iOS 26.2 (aus dem bestehenden Projekt übernommen, nicht geändert)
- Kein Backend, kein Account, keine Cloud. Alle Ressourcen sind lokal.

## Öffnen, bauen, starten

1. `DemonicRevAwakening OBD2.xcodeproj` in Xcode 26.3 oder neuer öffnen.
2. Schema **DemonicRevAwakening OBD2** wählen.
3. Ein Ziel wählen (Simulator oder iPhone) und **⌘R** drücken.
4. Tests laufen mit **⌘U**. Die Unit-Tests liegen in `DemonicRevAwakening OBD2Tests`, die UI-Tests in
   `DemonicRevAwakening OBD2UITests`.

Kommandozeile (Simulator, ohne Signatur):

```sh
xcodebuild test -project "DemonicRevAwakening OBD2.xcodeproj" \
  -scheme "DemonicRevAwakening OBD2" \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:"DemonicRevAwakening OBD2Tests" CODE_SIGNING_ALLOWED=NO
```

Der Workflow `.github/workflows/ios.yml` führt Build und Unit-Tests bei jedem Push auf
einem macOS-Runner aus.

## Signing mit deinem Apple-Developer-Team

Im Projekt ist bereits das Team `LWL7HM459L` mit *Automatically manage signing*
eingetragen. Es wurde nicht verändert.

1. Projekt › Target **DemonicRevAwakening OBD2** › *Signing & Capabilities*.
2. Unter *Team* dein Team wählen. Falls nötig: Xcode › Settings › Accounts › Apple-ID hinzufügen.
3. Die Bundle-ID `me.thedemonlord333.DemonicRevAwakening-OBD2` beibehalten.
4. Auf dem iPhone beim ersten Start gegebenenfalls *Einstellungen › Allgemein ›
   VPN & Geräteverwaltung* öffnen und dem Entwicklerzertifikat vertrauen. Ab iOS 16
   muss außerdem der Entwicklermodus aktiv sein.

Weitere Capabilities oder Hintergrundmodi sind nicht nötig und nicht aktiviert.

## Demo-Modus

Die Demo funktioniert ohne Adapter und im Simulator.

- Startbildschirm › **Demo**, oder **Verbinden** › *Demo*.
- **Automatisch**: Der Ablauf zeigt Motor aus, Motorstart, Leerlauf, einen Gasstoß,
  einen Drehzahlanstieg bis über 5.500 RPM und die Beruhigung. Der Ablauf wiederholt sich.
  Er lässt sich pausieren und neu starten.
- **Manuell**: Schieberegler von 0 bis 8.000 RPM.
- Die Demo nutzt **dieselbe** Dämonen-Logik wie Live-Daten.
- Solange sie läuft, ist **„Demo – simulierte Fahrzeugdaten“** sichtbar.
- Demo und Live schließen sich aus. Bricht eine Live-Verbindung ab, wechselt die App
  nie automatisch in die Demo. Das ist durch Unit-Tests abgesichert.

## Dämonenzustände

| Zustand | Bedingung (Standard, einstellbar) | Darstellung |
|---|---|---|
| Wartet auf Verbindung | weder Live noch Demo | gedämpft, Hörner glimmen schwach |
| Wartet auf Daten | verbunden, keine aktuelle Drehzahl (älter als 2,5 s) | eigener Wartezustand, keine erfundene Drehzahl |
| Schläft tief | gültig empfangene Drehzahl unter 250 RPM (Motor aus) | tiefer Atem, kaum Aura, „z“ |
| Schläft | bis 1.000 RPM | Augen zu, langsame Atmung, kleine Bewegungen |
| Erwacht | 1.000–2.000 RPM | Lider öffnen sich schrittweise, Kopf hebt sich, erstes grünes Leuchten |
| Wach | 2.000–3.500 RPM | offene, leuchtende Augen, sichtbare Aura, Blinzeln |
| Entfesselt | über 3.500 RPM | starkes Leuchten, Flammen und Funken, Fauchen, leichtes Beben |

Die Schwellen sind reine Animationswerte. Es sind keine empfohlenen Drehzahlen und keine
Motorschutzgrenzen. Diese Mechanismen sorgen für ruhige Übergänge:

- ±80 RPM Hysterese
- 0,45 s Mindestverweildauer
- zeitbasierte exponentielle Glättung, beim Anstieg schneller als beim Abfall

Die Energie wird zusätzlich stufenlos aus der Drehzahl berechnet. Ein schneller Anstieg
(über 2.500 RPM/s und über 400 RPM) löst eine kurze, weiche Reaktion aus. Einen Gangwechsel
leitet die App daraus nicht ab. Die Animation läuft mit eigener Bildrate und ist vom
OBD-Abfragetakt unabhängig.

## Architektur

```
DemonicRevAwakening OBD2/
  App/        App-Einstieg, AppModel (Verdrahtung, Lebenszyklus, Display-Sperre)
  Core/       plattformunabhängig: Einstellungen, Dämonen-Logik (DemonBrain),
              Demo-Engine, Datenquellen-Controller (Live/Demo, Wiederverbindung)
  OBD/        ELM327-Parser, PID-Dekodierung, OBDSession (Befehlswarteschlange), Transport-Protokoll
  Transport/  CoreBluetooth (BluetoothCentral, BLETransport), Network-Framework (TCPTransport)
  Demon/      Core-Graphics-Zeichnung der Körperteile (DemonArtwork), SpriteKit-Szene (DemonScene)
  UI/         SwiftUI-Oberfläche: Start, Drehzahlbogen, Verbinden, Einstellungen, Anleitung
```

Die Figur besteht aus getrennt animierten Ebenen:

- Körper (Atmung)
- Kopf (Heben, Neigen, Wiegen)
- Hörner mit eigener Leuchtebene
- Ohren (Zucken)
- Augen mit beschnittenen, beweglichen Oberlidern und eigenem Augenleuchten
- Brauen (grimmiger Blick)
- Maul (Fauchen) mit Leuchten
- Aura
- Flammen- und Funkenpartikel
- Nebel
- aufsteigende „z“

Bei Bluetooth und Network laufen alle Callbacks auf der Main-Queue. UI-Zustand und
OBD-Session leben auf dem MainActor.

## OBD2-Verbindung

### Gemeinsame ELM327-Schicht

- Initialisierung: `ATZ` (Ersatz `ATI`), `ATE0`, `ATL0`, `ATS1`, `ATH1`, `ATAT1`, `ATSP0`.
  Danach folgt `0100` mit langem Zeitlimit für die Protokollsuche, dann `ATDP`.
- Die Befehlswarteschlange ist seriell: Es ist immer nur ein Befehl unterwegs.
- Antwort-Fragmente werden bis zum Prompt `>` gepuffert. Echo, Leerzeilen, `SEARCHING...`,
  `BUS INIT` und NUL-Bytes werden entfernt.
- Erkannte Statusmeldungen: `NO DATA`, `STOPPED`, `UNABLE TO CONNECT`, `CAN ERROR`,
  `BUS ERROR`, `BUS BUSY`, `BUFFER FULL`, `?`, `DATA ERROR`, `LV RESET`/`ACT ALERT`.
- Bei einem Timeout werden verspätete Antworten verworfen. Sie werden nie dem nächsten
  Befehl zugeordnet.
- Unterstützte PIDs ermittelt die App aus der Bitmaske von `0100`.
- **Drehzahl `010C` hat Vorrang**: `((A × 256) + B) / 4`. Nur jede dritte Runde wird
  zusätzlich ein unterstützter Wert abgefragt: Geschwindigkeit (`0D`), Motorlast (`04`)
  oder Drosselklappenstellung (`11`). Die Drosselklappenstellung ist nicht die Gaspedalstellung.
- Antworten mehrere Steuergeräte, bleibt die App bei einer Quelle. Bevorzugt wird `7E8`,
  sonst wählt sie stabil sortiert.
- Abfragerate: höchstens etwa 10 Hz. Ohne Daten fragt die App langsamer ab. Die tatsächliche
  Rate wird angezeigt.
- Werte älter als 2,5 s gelten als **veraltet** und werden so angezeigt.
- Wiederverbindung mit Backoff von 1, 2, 4, 8, 15 und 30 s. Sie ist abschaltbar und kann
  manuell abgebrochen werden.
- Die App **liest nur**. Sie löscht keine Fehlercodes (kein Mode 04), codiert nichts und
  steuert nichts.

### Tatsächlich implementierte BLE-Adapterprofile

| Profil | Service | Notify | Write | Quelle |
|---|---|---|---|---|
| OBDLink CX | `FFF0` | `FFF1` | `FFF2` (Write / Write without Response) | OBDLink CX Adapter Notes: <https://support.obdlink.com/support/solutions/articles/43000746707-obdlink-cx-adapter-notes> |
| Eigenes Profil | frei | frei | frei | trägst du in den Einstellungen unter *Erweitert* ein |

Hinweise:

- Die OBDLink-Seite war aus der Entwicklungsumgebung nicht direkt abrufbar. Die
  UUIDs stammen aus Suchergebnissen, die diese Herstellerseite zitieren. **Vor dem
  Hardwaretest bitte gegenprüfen.** Die App prüft beim Verbinden ohnehin, ob es Dienst und
  Characteristics gibt und ob sie Notify bzw. Write unterstützen.
- Andere Adapter sind **nicht** vorkonfiguriert, weil dafür keine Herstellerdokumentation
  gefunden wurde. Ihre UUIDs kannst du mit einer BLE-Scanner-App (z. B. nRF Connect,
  LightBlue) auslesen und als eigenes Profil eintragen.
- Geräte in der Suche haben eine von drei Kennzeichnungen:
  - **Bewirbt den Dienst eines bekannten Profils**
  - **Name deutet auf ein Profil hin**: nur ein Hinweis
  - **Nicht konfiguriert / nicht unterstützt**
- Den Schreibmodus wählt die App nach Profil und den tatsächlichen
  Characteristic-Eigenschaften. Die Paketgröße kommt von
  `maximumWriteValueLength(for:)`. Bei *Write without Response* beachtet die App die
  Flusskontrolle über `canSendWriteWithoutResponse` und `peripheralIsReady(toSendWriteWithoutResponse:)`.
- **Klassische Bluetooth-Adapter (SPP)** sind mit iOS-Apps in der Regel nicht nutzbar.
  Das gilt auch für die meisten günstigen „Bluetooth 2.0“-ELM327. Adapter, die nur über
  MFi/External Accessory arbeiten (z. B. OBDLink MX+), unterstützt diese App nicht.

Verwendete Apple-Dokumentation:

- [Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [`CBPeripheral.maximumWriteValueLength(for:)`](https://developer.apple.com/documentation/corebluetooth/cbperipheral/maximumwritevaluelength(for:))
- [`NSBluetoothAlwaysUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription)
- [Network Framework / `NWConnection`](https://developer.apple.com/documentation/network/nwconnection)
- [`NSLocalNetworkUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)

### WLAN-Adapter einrichten

1. Adapter einstecken und die Zündung einschalten.
2. iPhone › Einstellungen › WLAN › das Netz des Adapters wählen (oft „WiFi_OBDII“,
   „V-LINK“ o. ä.). Das Netz hat meist kein Internet.
3. App › Verbinden › **WLAN**: IP-Adresse und Port eintragen. Viele ELM327-WLAN-Adapter
   nutzen `192.168.0.10:35000`. Das ist nur die Voreinstellung. Maßgeblich ist die
   Anleitung deines Adapters.
4. Die iOS-Abfrage **„Lokales Netzwerk“** erlauben. Falls sie verweigert wurde:
   Einstellungen › Datenschutz & Sicherheit › Lokales Netzwerk.

Eingetragene Info.plist-Schlüssel (über die Build-Einstellungen generiert):

- `NSBluetoothAlwaysUsageDescription`
- `NSLocalNetworkUsageDescription`
- `CFBundleDisplayName`

Hintergrundmodi sind keine aktiviert. Beim Wechsel in den Hintergrund trennt die App die
Verbindung sauber und baut sie im Vordergrund neu auf.

## Einstellungen (lokal in UserDefaults)

- Drehzahlschwellen und Skalenende. Die Reihenfolge wird validiert und erzwungen.
- Animationsintensität, Augenleuchten, Partikel, reduzierte Effekte.
- Display während einer Sitzung eingeschaltet lassen. Beim Verlassen stellt die App den
  ursprünglichen Zustand wieder her.
- Automatische Wiederverbindung.
- Letzter Adapter und letztes Profil, WLAN-Host und -Port, eigenes BLE-Profil.
- „Standardwerte wiederherstellen“ setzt Schwellen und Darstellung zurück und behält
  die Verbindungsdaten.

Barrierefreiheit:

- „Bewegung reduzieren“ wird berücksichtigt: weniger Bewegung, kein Beben, kein
  Nebeldrift.
- VoiceOver-Beschriftungen sind vorhanden.
- Bedienelemente sind mindestens 44 pt groß.
- Es gibt keine Blitz- oder Stroboskopeffekte. Alle Pulse liegen unter 1 Hz und sind weich.

## Bekannte Einschränkungen

- Die Kompatibilität mit konkreten Adaptern und Fahrzeugen ist **nicht mit Hardware geprüft**.
  Das gilt auch für den vorgesehenen Honda Jazz 2015.
- Mitgeliefert ist nur das OBDLink-CX-Profil. Andere BLE-Adapter brauchen ein eigenes Profil.
- Keine Unterstützung für klassische Bluetooth-SPP- und MFi-Adapter.
- Keine Hintergrundverbindung und keine Hintergrundanimation.
- Mehrteilige ISO-TP-Antworten werden nicht ausgewertet. Für die verwendeten PIDs sind sie
  nicht nötig.
- Die Figur ist programmatisch mit Core Graphics gezeichnet und nimmt das Icon als Vorlage.
  Es ist keine 1:1-Kopie des gemalten Icons.

## Echter Hardwaretest – Schritte

1. App mit deinem Team signieren und auf dem iPhone installieren (siehe oben).
2. **Im Stand** Adapter einstecken und die Zündung einschalten (noch ohne Motor).
3. Verbinden:
   - **BLE**: Verbinden › Bluetooth LE › Suche.
     - Erscheint der Adapter als *erkannt*? Mit Profil verbinden.
     - Bei einer Meldung „Dienst nicht gefunden“ die UUIDs mit nRF Connect prüfen und als
       eigenes Profil eintragen.
   - **WLAN**: Adapter-WLAN wählen, IP und Port eintragen, lokales Netzwerk erlauben.
4. Erwartung bei Zündung an und Motor aus: Status *Live*, der Dämon „Schläft tief“ (0 RPM)
   oder „Wartet auf Daten“ (`NO DATA`).
5. Motor starten. Die Leerlaufdrehzahl muss plausibel sein, beim Jazz etwa 700–900 RPM. Den
   Wert mit dem Drehzahlmesser im Cockpit vergleichen.
6. Im Stand vorsichtig kurz Gas geben. Der Dämon erwacht und schläft danach wieder ein.
7. Prüfen, ob Geschwindigkeit, Motorlast und Drosselklappe erscheinen. Sie erscheinen nur,
   wenn das Fahrzeug sie meldet.
8. Abbruchtest: Adapter abziehen. Erwartet wird *Verbindung unterbrochen*, dann
   Wiederverbindungsversuche und **keine** Demo-Daten. Adapter wieder einstecken: Die
   Verbindung baut sich neu auf.
9. App in den Hintergrund und zurück: Die Sitzung wird fortgesetzt.
10. Ergebnisse notieren: Adaptermodell, Firmware (`ATI`-Antwort im Status), Protokoll und
    Abfragerate.

Sicherheit: Einrichtung nur im Stand. Während der Fahrt die App nicht bedienen.
