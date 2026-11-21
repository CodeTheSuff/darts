# Architektur Darts 3.0.0 – Web-App + Vermittlungs-Server

Stand: Phase 1 (2026-11-21). Dieses Dokument ist der **Vertrag** zwischen den parallel arbeitenden Agenten.
Änderungen an Schnittstellen nur nach Absprache (in Phase 3 zusammenführen). Auftrag insgesamt: `docs/PROMPT_WEB_UMZUG.md`.

## 1. Überblick

```
 iPhone/Browser (Web-App)  ─┐
 Android-APK (Online)      ─┼──  wss://<server>/ws  ──  Vermittlungs-Server (Dart, Relais)
 Android-APK (Online)      ─┘                            liefert auch Web-App, /version.json, /apk/…
 Android-APK  ── WLAN (bisherige Kopplung, ohne Internet) ── Android-APK
```

- **Host = Schiedsstelle** bleibt wie bisher: Ein Gerät (Host) führt das Spiel, Gäste schicken Würfe, der Host verteilt den Stand.
  Online kann **jedes** Gerät Host sein – auch ein iPhone im Browser.
- Der Server ist ein **dummes Relais**: Er versteht die Spiel-Nachrichten nicht, er reicht sie nur weiter.
  Über ihn läuft **dasselbe Link-Protokoll** wie im WLAN (`hello`, `auth`, `auth2`, `welcome`, `pending`, `denied`, `state`,
  `dart`, `undo`, `start`, `board`, `boardNo`, `mode`, `share`, `have`, `syncpkg`, `syncreq`, `direct`).
  Dadurch bleiben Freigabe durch den Host, Geräte-Schlüssel (HMAC), Abgleich und Turnier-Logik **unverändert**.

## 2. Gemeinsames Paket `packages/darts_protocol` (fertig in Phase 1, eingefroren)

- `RelayFrame` – Umschläge zwischen Client und Server (siehe Kommentar in `lib/src/frames.dart`):
  - Client→Server: `host`, `join`, `to`, `all`, `d`, `kick`, `ping`
  - Server→Client: `hosted`, `joined`, `peer+`, `peer-`, `from`, `d`, `hostOffline`, `hostOnline`, `closed`, `error`, `pong`
  - Das Feld `d` enthält die **unveränderte Link-Nachricht als JSON-String**.
- `RelayLimits` – Grenzen (4 MB je Frame, 8 Gäste je Raum, Rate-Limit, Sperre nach falschen Codes, Ping 15 s / Timeout 45 s).
- `RelayError` – Fehlercodes `noRoom, full, update, rate, bad, token, busy`.
- `RoomCode` – 6 Zeichen aus `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (Anzeige „K7M 2QX“), `randomToken()` für das Host-Token.
- `VersionInfo` – Inhalt von `/version.json` (`version`, `build`, `minProtocol`, `apk`, `notes`).
- `relayProtocol = 3`, `relayPath = '/ws'`.

Wer etwas am Paket ändern muss: **nicht** selbst ändern, sondern im Abschlussbericht melden (Phase 3 entscheidet).

## 3. Raum-Lebenszyklus auf dem Server

1. Host sendet `{r:host, proto, app}` → Server erzeugt Raum-Code + Token → `{r:hosted, room, token}`.
   Die App merkt sich `room` + `token` (Store) für Wiederverbindung.
2. Host sendet später erneut `{r:host, room, token}` (App-Neustart, Netzwechsel) → Raum wird zurückgeholt (`resumed:true`),
   Gäste bekommen `hostOnline`. Falsches Token → `error token`. Ist der Raum frei/abgelaufen und das Format gültig,
   darf der Server ihn mit **demselben Code** neu anlegen (dann bleibt der Code für Gäste gleich).
3. Gast sendet `{r:join, room}` → `{r:joined, peer:'p3', hostOnline}`; Host bekommt `{r:peer+, peer:'p3'}`.
   Danach läuft das normale Link-Protokoll (Gast schickt `hello` …) eingepackt in `d`/`from`/`to`.
4. Host weg (Verbindung zu) → Gäste bekommen `hostOffline`, Raum bleibt bestehen.
5. Raum wird gelöscht, wenn **24 h** (`ROOM_TTL_HOURS`) keine Aktivität war **oder** der Host ihn bewusst schließt:
   Schließt der Host seine Verbindung mit WebSocket-Close-Code **4000** („Raum schließen“ in der App), ist der Raum
   sofort weg und alle Gäste bekommen `closed`. Jede andere Trennung gilt nur als „Host offline“.
6. **Zwischenspeicher (Entscheidung „kurz zwischenspeichern“):** Der Server merkt sich je Raum nur Metadaten
   (Code, Token-Hash, Zeitstempel, verbundene Peers) im **Arbeitsspeicher**. Spielstände/Namen werden **nicht** gespeichert –
   der laufende Spielstand liegt ohnehin auf dem Host-Gerät (`Store.activeMatch`) und wird nach dem Zurückholen
   über das normale `state` neu verteilt. So bleibt der Raum 24 h nutzbar, ohne dass personenbezogene Daten auf dem Server liegen.
   → in `docs/web_fortschritt.md` unter „Bitte prüfen“ vermerkt.

Sicherheit (Server): Rate-Limit je Verbindung, Sperre je IP nach `maxBadJoins` falschen Codes, max. Frame-Größe,
max. Räume (`MAX_ROOMS`), Hello-Timeout, Idle-Timeout, keine Spielernamen/Inhalte in Logs, Token nur als Hash speichern.
Zusätzlich bleibt die **Freigabe am Host** (neues Gerät muss bestätigt werden) – der Raum-Code allein reicht nicht.

## 4. App-Seite

### 4.1 Transport-Abstraktion (`lib/net/`)
`Link` arbeitet künftig nicht mehr direkt mit `dart:io`-WebSockets, sondern mit einer kleinen Schnittstelle:

```dart
/// Eine Verbindung zu einem Gegenüber (Gast aus Host-Sicht bzw. Host aus Gast-Sicht).
abstract class PeerSocket {
  Stream<String> get messages;      // eingehende Link-Nachrichten (JSON-Strings)
  void send(String data);           // ausgehende Link-Nachricht
  Future<void> close();
  Future<void> get done;            // endet bei Trennung
  String get remote;                // IP (WLAN) bzw. "relay:p3" (online) – nur für Sperrliste/Logs
}
```

- `lan_io.dart` (nur Android, `dart:io`): HttpServer/WebSocket, UDP-Suche, Netzsuche, MethodChannel – der heutige Code.
- `lan_stub.dart` (Web): alles „nicht verfügbar“. Einbindung per Conditional Import (`if (dart.library.io)`).
- `relay.dart` (überall, `web_socket_channel`): Verbindung zum Server; als Host liefert sie je Gast einen virtuellen
  `PeerSocket`, als Gast einen `PeerSocket` zum Host. Ping alle 15 s, automatische Wiederverbindung (Host mit Token).
- `Link` bekommt einen **Modus** `LinkMode { lan, online }`. Online-Host: `startOnlineHost()`, Online-Gast: `joinOnline(code)`.
  Alles oberhalb (Freigabe, Schlüssel, `state`, Abgleich, `LinkCoordinator`) bleibt gleich.
- Im **Web** gibt es nur `online`. Die UI blendet WLAN-Teile aus (`kIsWeb`).

### 4.2 Server-Adresse
- `lib/net/server_config.dart`: **eine** Stelle für die Produktiv-Adresse (`defaultServerUrl`, vorerst Platzhalter
  `https://darts.example.invalid` – **offener Punkt**), dazu `Store.serverUrl` (Überschreibung in den Einstellungen, z. B.
  `http://192.168.0.10:8080` zum Testen).
- Web: Standard ist **die eigene Herkunft** (`Uri.base.origin`) – die Web-App wird vom selben Server ausgeliefert.
- `http://` → `ws://`, `https://` → `wss://`, Pfad `relayPath`.

### 4.3 Update
- Beim Start und beim Online-Koppeln (max. 1×/Tag, außer bei `error update`) `GET <server>/version.json`.
- APK: ist `build > appBuild` → Dialog „Neue Version x.y.z“ mit Änderungsliste → „Herunterladen“ öffnet `apk`-URL
  per `url_launcher` (Browser lädt, Android installiert). Kein eigener Installer nötig.
- Web: ist eine neuere Version da → Banner „Neue Version – neu laden“ (Service Worker aktualisieren + reload).
- `error update` vom Relais → derselbe Dialog sofort.
- `appBuild` steht in `lib/ui/about_screen.dart` (muss zu `pubspec.yaml` passen, aktuell 19).

### 4.4 Web-Tauglichkeit (ohne Kopplung)
- `ErrorLog`: Datei-Zugriff (`dart:io`, `path_provider`) nur auf Android; im Web im Speicher + localStorage (begrenzt).
- Backup-Export im Web als Datei-Download, Import per Datei-Auswahl (file_picker kann Web).
- Ton: iOS braucht eine Nutzer-Geste vor dem ersten Ton (Audio-Unlock beim ersten Tippen).
- Vibration im Web still ignorieren. Bildschirm wach halten: Screen Wake Lock API (wakelock_plus Web).
- Speicher: `navigator.storage.persist()` anfragen; Hinweis „Zum Home-Bildschirm hinzufügen“ (iOS Safari, nicht installiert),
  Erinnerung an Backups. Safe-Area beachten.
- PWA: `web/manifest.json` (Name „Darts“, Farben, Icons aus `assets/icon`), `apple-touch-icon`, Start offline möglich,
  `<base href>` über `--base-href` steuerbar.

## 5. Zuständigkeiten (wer darf welche Dateien ändern)

| Agent | Bereich | Dateien |
|---|---|---|
| **A Server** | Relais-Server | `server/**` (eigenes Dart-Paket, hängt per path von `packages/darts_protocol` ab) |
| **B Web** | Web-Tauglichkeit, PWA, iOS | `web/**`, `lib/data/error_log.dart` (+ neue `lib/data/error_log_*.dart`), `lib/platform/**` (neu), `lib/data/sound.dart`, `lib/ui/settings_screen.dart` (nur Backup/Hinweise), `lib/ui/home_screen.dart` (nur Install-/Backup-Hinweis), `lib/main.dart` (nur Init-Aufrufe), Tests `test/web_*` |
| **C Kopplung** | Online-Kopplung, Update | `lib/net/**`, `lib/ui/link_coordinator.dart`, `lib/ui/link_screen.dart`, `lib/ui/update_dialog.dart` (neu), `lib/data/storage.dart` (**nur neue** Felder: serverUrl, onlineRoom, onlineToken, KnownHost-Online-Angaben, lastUpdateCheck), `android/app/src/main/AndroidManifest.xml` (falls nötig), Tests `test/net_*`, bestehende Link-Tests anpassen |
| **D Paket** | Hosting & E2E | `deploy/**`, `tool/build_release.ps1`, `ANLEITUNG_HOSTING.md`, `docs/ios_testliste.md`, `tool/e2e/**` |

Gemeinsam genutzt, aber in Phase 1 schon vorbereitet: `pubspec.yaml` (Abhängigkeiten `darts_protocol`, `web_socket_channel`,
`url_launcher`, `web` sind drin – **keine** weiteren App-Abhängigkeiten ohne Not; falls doch: im Bericht nennen).
`lib/ui/tutorial/**`, `lib/ui/about_screen.dart` (Changelog) und Versionsnummern macht **Phase 3**.

## 6. Tests

- Alle bestehenden Tests (Stand 2.10.1: 322) müssen grün bleiben: `flutter test`.
- A: `server/test/` – Räume, Weiterleitung, Token/Zurückholen, TTL, Limits, Rate-Limit, Sperre, `/version.json`, `/health`,
  statische Auslieferung. Mehrere simulierte Clients über echte WebSockets (`dart test` in `server/`).
- B: `flutter build web` fehlerfrei; Tests für Plattform-Weichen (mit `kIsWeb`-Abstraktion testbar machen).
- C: `test/net_*` – Relay-Transport gegen einen **kleinen In-Test-Relais** (minimaler Server im Test auf Basis von
  `darts_protocol` + `dart:io` HttpServer) **oder** gegen `server/` falls schon da; bestehende Link-/Sync-Tests weiter grün.
- D: `tool/e2e/` – Skript, das den Server startet und 2–3 Dart-Clients (reine WebSocket-Clients mit Link-Nachrichten
  im Umschlag) ein kurzes Spiel durchspielen lässt; läuft in Phase 3 gegen das Ergebnis von A und C.

## 7. Konventionen
- Deutsch in Kommentaren und UI-Texten, Stil wie im bestehenden Code.
- Keine Schlüssel/Passwörter anfassen (`android/key.properties`, `C:\dev\darts_keys`).
- Häufig committen (im eigenen Worktree-Branch). Commit-Nachrichten auf Deutsch.
