# Prompt: Darts 3.0.0 – Web-App (auch für iPhone) + Online-Kopplung über Server

> Diesen gesamten Text in einer neuen Claude-Code-Sitzung im Ordner `C:\dev\darts_counter` einfügen.
> Am besten abends starten: Wenn das Token-Limit erreicht ist, macht Claude Code automatisch weiter
> (`autoContinueAtUsageLimit` ist an). Der PC muss dafür am Netzteil bleiben und die Sitzung offen sein.

---

## Auftrag

Baue Version **3.0.0** der Darts-App (`C:\dev\darts_counter`, Flutter). Es gibt drei Ergebnisse:

1. **Web-App (PWA):** dieselbe App als Website, damit iPhone- und iPad-Nutzer sie im Browser nutzen
   und auf den Home-Bildschirm legen können.
2. **Vermittlungs-Server (Dart):** Er liefert die Web-App aus und vermittelt Spiele zwischen Geräten über das Internet
   (Raum-Code), auch von verschiedenen Orten aus.
3. **APK 3.0.0:** Sie koppelt zusätzlich über den Server, damit Android- und iPhone-Spieler zusammen spielen können.
   Die bisherige WLAN-Kopplung bleibt als Rückfallebene ohne Internet. Dazu kommt ein Selbst-Update über den Server.

Zum Schluss entsteht ein **ZIP-Paket für einen Freund**, der die App auf seinem Server hostet. Es enthält eine Anleitung
für ihn. Alles wird vorher **komplett lokal hier am PC getestet**.

Halte dich an meine globalen Anweisungen (CLAUDE.md) und an die Projekt-Memory, vor allem an diese Punkte:
- Antworten auf Deutsch.
- Die neueste APK als `APK\Darts_<version>.apk` ablegen. Installation nur mit `adb install -r`.
- Bei jeder App-Änderung die kurze Einführung und das große Tutorial anpassen.
- Am Ende eine Push-Benachrichtigung senden.
- Der Release-Schlüssel liegt in `android/key.properties` bzw. `C:\dev\darts_keys`. Er darf **niemals** committet,
  ins ZIP gepackt oder weitergegeben werden.

## Bereits getroffene Entscheidungen (nicht erneut fragen)

| Thema | Entscheidung |
|---|---|
| Funktionsumfang Web | **Alles** wie die APK: X01, Training, Minispiele, Turnier, Statistik, Bots, Anzeige-Modus (Tablet/TV) |
| Datenspeicherung | **Nur auf dem Gerät** wie bisher (shared_preferences → im Browser localStorage). Kein Login, keine Konten |
| Gemeinsames Spielen | Über den Server per Raum-Code, **auch von verschiedenen Orten** |
| APK-Kopplung | **Server + WLAN als Fallback** (bestehende LAN-Kopplung bleibt erhalten) |
| Server speichert | **Kurz zwischenspeichern:** letzter Spielstand je Raum bis zu **24 h** im Arbeitsspeicher, damit nach Verbindungsabbruch weitergespielt werden kann. Keine Datenbank, nichts auf der Festplatte, keine Spielernamen in Logs |
| Server-Sprache | **Dart** (shelf + shelf_web_socket o. ä.), damit Protokoll/Modelle mit der App geteilt werden können |
| Updates zum Freund | **ZIP-Datei** (kein Git-Zugang für ihn) |
| Name | **„Darts“**, gleiches Logo wie die APK |
| Version | **3.0.0** für APK und Web gleichzeitig. Ab jetzt tragen beide immer dieselbe Nummer |
| Alte APKs | Über den Server: Hinweis „Bitte aktualisieren“ **mit direktem Download** der neuen APK vom Server. Im WLAN koppeln alte und neue APK weiter. Hinweis: 2.10.1 kennt den Server noch nicht, sie muss einmal manuell auf 3.0.0 aktualisiert werden |
| Tests | Lokal am PC und im Heim-WLAN. Für den iPhone-Test kurz ein **Cloudflare-Quick-Tunnel** (cloudflared, ohne Konto), danach wieder beenden |
| iPhone zum Testen | Leihgerät von Freund/Familie → iOS-Tests **gebündelt am Ende**, vorher mit einer Checkliste vorbereiten |

## ⚠️ Offener Punkt (merken, NICHT blockieren)

**Unbekannt ist noch, was für einen Server der Freund hat** (Linux mit/ohne Docker, nur Webspace, NAS?) und ob er eine
(Sub-)Domain mit HTTPS hat. Daraus folgt:
- Alles andere bauen und testen, ohne darauf zu warten.
- Das Hosting-Paket so bauen, dass es **beide Wege** abdeckt:
  - **a) Docker:** `docker compose up -d`, optional mit Caddy für automatisches HTTPS.
  - **b) Ohne Docker:** fertig kompilierte Server-Datei für Linux + systemd-Dienst + Beispielkonfiguration für nginx/Caddy.
- In `docs/web_fortschritt.md` und in der Memory gut sichtbar festhalten: „Server-Art und Domain des Freundes klären“.
- Reiner Webspace ohne eigene Prozesse kann den Vermittlungs-Server **nicht** betreiben. Dann Simon am Ende
  die Alternativen nennen (z. B. Web-App auf dem Webspace und den kleinen Server bei einem günstigen Anbieter), aber nichts davon selbst buchen.

---

## Technische Leitplanken

### Kopplung (Herzstück)
- Heute (`lib/net/link.dart`, `lib/ui/link_coordinator.dart`, `lib/data/sync.dart`):
  - Ein Handy ist Host mit eigenem WebSocket-Server (`dart:io`), Gäste finden es per UDP-Broadcast bzw. Suche im Netz.
  - Raum-Code, Host ist die Spiel-Autorität, Gäste senden `dart`/`undo` usw.
  - Diese Logik (Host = Autorität) **beibehalten**. Der Server ist nur ein **Relais**.
- Neue **Transport-Abstraktion** in `lib/net/`:
  - `LanTransport`: die bestehende Technik, nur auf Android (`dart:io`), über **Conditional Imports**, damit der Web-Build kompiliert.
  - `RelayTransport`: WebSocket zum Server (`web_socket_channel`, läuft auf Web und Android).
  - Darüber bleiben die bestehenden Nachrichten (`dart`, `undo`, `start`, `board`, Sync …) möglichst unverändert.
- Raum per Raum-Code:
  - Der Server ordnet Verbindungen dem Raum zu, ein Teilnehmer ist Host.
  - Fällt der Host weg, bekommen die Gäste einen klaren Status und das Spiel kann nach Reconnect weiterlaufen
    (Snapshot aus dem 24-h-Zwischenspeicher).
- **Protokoll-Version** im Handshake. Bei einer zu alten Version gibt es eine verständliche Meldung samt Update-Link.
- Sicherheit:
  - Raum-Codes nicht erratbar genug machen (Länge prüfen, ggf. verlängern).
  - Rate-Limits, maximale Nachrichtengröße, maximale Teilnehmer pro Raum, Timeouts.
  - Nur `wss://` im Betrieb.
- UI im Koppeln-Bildschirm:
  - Auswahl „Online (über Server)“ und „Im WLAN“. Web zeigt nur „Online“.
  - Einstellung „Server-Adresse“ mit vorbelegter Produktiv-Adresse. Die ist noch unbekannt, also als Platzhalter
    an **einer** Stelle konfigurieren. Zum Testen lässt sie sich überschreiben (z. B. `http://<PC-IP>:8080`).

### Web-Tauglichkeit
- `dart:io`-Stellen (`lib/net/link.dart`, `lib/data/error_log.dart`, ggf. weitere) über Conditional Imports bzw. Plattform-Weichen.
- Plugins prüfen und notfalls ersetzen: `share_plus`, `file_picker`, `path_provider`, `wakelock_plus`, `audioplayers`.
  Backup-Export und -Import müssen im Browser funktionieren (Download bzw. Datei-Upload).
- **iOS-Safari-Besonderheiten:**
  - Ton erst nach der ersten Berührung freischalten (Audio-Unlock).
  - Vibration gibt es nicht (still ignorieren).
  - Bildschirm wach halten über die Screen Wake Lock API, wo verfügbar.
  - Safe-Area/Notch beachten.
  - 100vh-Problem vermeiden.
- **Datenverlust auf iOS verhindern:**
  - `navigator.storage.persist()` anfragen.
  - Ohne Home-Bildschirm-Installation einen Hinweis „Zum Home-Bildschirm hinzufügen“ mit kurzer Anleitung für Safari zeigen.
  - Regelmäßig an das Backup erinnern.
- **PWA:**
  - `manifest.json` (Name „Darts“, Icons aus `assets/icon`, `display: standalone`, Theme-Farben).
  - `apple-touch-icon` und Service Worker für den Offline-Start.
  - `base href` konfigurierbar, falls die App unter einem Unterpfad liegt.
- Der Anzeige-Modus (`scoreboard_screen`, `tournament_display`, `display_waiting`) muss im Browser im Vollbild laufen.

### Selbst-Update der APK (ab 3.0.0)
- Der Server liefert `/version.json` (Version, versionCode, Download-URL, Änderungsliste) und `/apk/Darts_<version>.apk`.
- Die APK prüft beim Start und beim Koppeln (höchstens 1× pro Tag). Ist eine neuere Version da:
  Dialog → Download → Android-Installer. Am einfachsten über den Browser bzw. `url_launcher`. Ein In-App-Installer ist nur sinnvoll,
  wenn er sauber geht (Berechtigung `REQUEST_INSTALL_PACKAGES`).
- Die Web-App zeigt nach einem Update „Neue Version verfügbar – neu laden“.

### Server (`/server`, eigenes Dart-Paket)
- Liefert den Web-Build (statische Dateien) aus und bietet `/ws` (WebSocket), `/version.json`, `/apk/…` und `/health`.
- Konfiguration nur über Umgebungsvariablen: `PORT`, `PUBLIC_URL`, `ROOM_TTL_HOURS=24`, `MAX_ROOMS`, `MAX_PEERS_PER_ROOM`, `LOG_LEVEL`.
- Ressourcenbedarf klein halten (Ziel: < 100 MB RAM). Kompilierbar mit `dart compile exe`.
- Logs ohne personenbezogene Daten.

### Hosting-Paket für den Freund
- `deploy/` mit:
  - `Dockerfile` (mehrstufig: Web-Build + Server-Binary)
  - `docker-compose.yml` (optional mit Caddy-Service für automatisches HTTPS)
  - `Caddyfile`- und `nginx`-Beispiel
  - `darts.service` (systemd) und `.env.example`
- Skript `tool/build_release.ps1`. Es baut Web-App, Server (Linux-Binary per Docker-Build oder Anleitung) und APK und legt
  `release\darts_server_<version>.zip` an. Inhalt:
  - Web-Build, Server, aktuelle APK, `version.json`
  - `deploy/`-Dateien
  - `ANLEITUNG_HOSTING.md`
  - **ohne** Schlüssel und Passwörter
- `ANLEITUNG_HOSTING.md` (Deutsch, für einen technisch versierten Freund):
  - Voraussetzungen: Linux-Server, offene Ports 80/443, (Sub-)Domain, Docker *oder* systemd.
  - Installation in wenigen Schritten, HTTPS-Einrichtung, Update per neuem ZIP (Ablauf + Befehle).
  - Prüfen per `/health`, Logs ansehen, Ressourcenbedarf.
  - Datenschutz-Hinweis: kein dauerhafter Speicher, Räume verfallen nach 24 h.
  - Was tun bei reinem Webspace.

---

## Vorgehen in 3 Phasen (mehrere Agenten, wo es sinnvoll ist)

### Phase 1 – allein (Planung und Fundament)
1. Den bestehenden Code lesen: `lib/net/link.dart`, `lib/ui/link_coordinator.dart`, `lib/ui/link_screen.dart`,
   `lib/data/sync.dart`, `lib/data/storage.dart`, `lib/data/error_log.dart`, `pubspec.yaml`.
2. Einen Probe-Build `flutter build web` machen und alle Fehler auflisten.
3. `docs/web_architektur.md` schreiben:
   - Protokoll (Nachrichten, Handshake, Protokoll-Version, Raum-Lebenszyklus, Reconnect/Snapshot)
   - Transport-Interface
   - Ordner- und Datei-**Zuständigkeiten je Agent**, damit sich niemand in dieselben Dateien schreibt
   - Teststrategie
4. Gemeinsame Grundlagen anlegen und committen:
   - Transport-Interface und Protokoll-Konstanten als **gemeinsames Dart-Paket** (z. B. `packages/darts_protocol`),
     das App und Server beide nutzen.
   - Leere Ordner `server/` und `deploy/`.
   - Versionsnummer auf 3.0.0.
5. `docs/web_fortschritt.md` anlegen: eine Checkliste aller Schritte, die laufend abgehakt wird.

### Phase 2 – parallel, 4 Agenten mit `isolation: "worktree"`
Jeder Agent bekommt `docs/web_architektur.md` als Grundlage. Er arbeitet nur in seinen Dateien, testet selbst und committet
in seinem Worktree-Branch. Zum Schluss meldet er kurz, was fertig ist und was offen bleibt.

- **Agent A – Server:**
  - `server/` umsetzen: Räume, Relais, 24-h-Snapshot, Limits, `/version.json`, `/apk`, `/health`, statische Auslieferung.
  - Unit- und Integrationstests (mehrere simulierte Clients, Reconnect, TTL, Limits).
- **Agent B – Web-Tauglichkeit der App:**
  - Conditional Imports und Plattform-Weichen, Plugin-Ersatz, PWA-Dateien (`web/`), iOS-Besonderheiten.
  - Hinweis „Zum Home-Bildschirm“, Speicher-Persistenz, Backup im Browser.
  - Ziel: `flutter build web` fehlerfrei und alle Modi im Chrome-Desktop spielbar.
- **Agent C – Kopplung in der App:**
  - `RelayTransport` und Umbau von Link und LinkCoordinator auf die Transport-Abstraktion, ohne dass die WLAN-Kopplung kaputtgeht.
  - Koppeln-UI (Online/WLAN, Server-Adresse), Protokoll-Version und Update-Hinweis, Selbst-Update der APK.
  - Tests für den Transport (gegen einen Test-Server aus dem gemeinsamen Paket bzw. einen Mock).
- **Agent D – Paket, Anleitung und Ende-zu-Ende-Tests:**
  - `deploy/`, `tool/build_release.ps1`, `ANLEITUNG_HOSTING.md`.
  - Ein Testskript, das den Server lokal startet und zwei bis drei Clients ein komplettes X01-Spiel über den Server spielen lässt.
  - Die iOS-Checkliste `docs/ios_testliste.md` für den späteren Test mit dem Leihgerät.

Faustregel: Parallel arbeiten nur Teile, die verschiedene Dateien betreffen. Hängt etwas voneinander ab, wartet
der abhängige Agent auf das Ergebnis, statt zu raten.

### Phase 3 – allein (Zusammenführen und Abschluss)
1. Die Worktree-Branches nacheinander nach `main` mergen und Konflikte lösen.
2. Prüfen:
   - `flutter analyze` sauber
   - **alle** bestehenden Tests (Stand 2.10.1: 322) plus die neuen grün
   - `flutter build web` und `flutter build apk --release`
3. **Lokaler Gesamttest:**
   - Server am PC starten.
   - Chrome am PC, Android-APK (Server-Adresse `http://<PC-IP>:8080`) und Tablet im WLAN spielen gemeinsam
     X01, ein Training und ein kleines Turnier.
   - WLAN-Kopplung ohne Server weiterhin prüfen.
   - Anzeige-Modus im Browser prüfen.
   - Bedien-Tests auf den Geräten macht Simon selbst. Du installierst nur und bereitest die Testanleitung vor.
4. **Tutorial und Einführung:**
   - Neues Kapitel „Online spielen und iPhone“ (Web-App öffnen, zum Home-Bildschirm hinzufügen, Online-Raum, Backup).
   - Koppeln-Kapitel anpassen, kurze Einführung anpassen.
   - Changelog 3.0.0.
5. `APK\Darts_3.0.0.apk` ablegen. Ist ein Gerät angesteckt: `adb install -r`.
6. ZIP mit `tool/build_release.ps1` bauen und den Inhalt prüfen: **keine** Schlüssel, Passwörter oder `key.properties`.
7. **iPhone-Test vorbereiten:**
   - `cloudflared` portabel nach `C:\dev\tools\` laden.
   - **Vor dem Start Simon fragen.** Dann `cloudflared tunnel --url http://localhost:8080` starten und Simon die
     Adresse samt `docs/ios_testliste.md` geben.
   - Nach dem Test den Tunnel beenden.
8. Committen (ohne `BilderLayout/` und Schlüssel), Memory aktualisieren und eine Push-Benachrichtigung senden.

## Wenn das Token-Limit erreicht wird / über Nacht
- Nach **jedem** abgeschlossenen Schritt `docs/web_fortschritt.md` aktualisieren und häufig committen. So kann jede
  Fortsetzung (auch nach Kontext-Zusammenfassung) genau dort weitermachen.
- Keine Rückfragen mitten in der Nacht, die alles blockieren: Wo eine Entscheidung offen ist, die sinnvollste
  Variante wählen und sie in `docs/web_fortschritt.md` unter „Bitte prüfen“ notieren.
- **Ausnahmen, bei denen gewartet und gefragt wird:** Tunnel starten, irgendetwas ins Internet senden, Konten anlegen
  oder etwas kaufen, Schlüssel anfassen, Geräte-Daten löschen.

## Ergebnis, das Simon am Ende bekommt
1. APK 3.0.0, installiert bzw. im APK-Ordner.
2. `release\darts_server_3.0.0.zip` für den Freund.
3. Eine kurze Zusammenfassung mit:
   - was getestet ist und was noch nicht (v. a. iOS)
   - was der Freund braucht: Server-Voraussetzungen, Domain/HTTPS, was er mit dem ZIP tun muss
   - die offenen Punkte (Server-Art und Domain des Freundes)
