# Fortschritt Darts 3.0.0 (Web-App + Server)

Grundlage: `docs/PROMPT_WEB_UMZUG.md`, Architektur: `docs/web_architektur.md`.

## ⚠️ Offen (klären mit Simon / Freund)
- Server-Art des Freundes (Docker / Linux ohne Docker / Webspace?) und Domain mit HTTPS – Paket deckt Docker + systemd ab.
- Produktiv-Server-Adresse unbekannt → Platzhalter an einer Stelle.

## Phase 1 – Planung & Fundament (allein)
- [x] Code der Kopplung gelesen (link.dart, link_coordinator.dart, link_screen.dart, sync.dart, storage.dart, error_log.dart)
- [x] Probe-Build `flutter build web` + Fehlerliste → kompiliert! dart:io scheitert erst zur Laufzeit (Link, ErrorLog/path_provider)
- [x] docs/web_architektur.md (Protokoll, Transport, Zuständigkeiten, Tests)
- [x] Gemeinsames Paket packages/darts_protocol + Ordner server/, deploy/
- [x] Version 3.0.0
- [x] Commit Phase 1

## Phase 2 – parallel (4 Agenten, Worktrees) – gestartet 2026-11-21 nach Commit dd5480d
- [x] A Server – gemergt (81d7ae0), 38 Tests grün, Linux-Cross-Kompilierung ok, Leerlauf 15 MB RAM
- [x] B Web-Tauglichkeit – gemergt (cb9e066), 335 Tests, Web-Build ok, headless Edge: Start/X01/Backup/Offline ok
- [x] C Kopplung in der App – gemergt (200b47e), 352 Tests; Integrationstest gegen echten Server 5/5
- [x] D Paket, Anleitung, E2E-Tests – gemergt (7e8f2cd), E2E 9/9 grün gegen echten Server

## Phase 3 – Zusammenführen (allein)
- [x] Merge aller Branches
- [x] analyze + alle Tests + build web + build apk
- [x] Lokaler Gesamttest: Browser (headless Edge) ↔ App über echten Server in beide Richtungen, lokales X01 im Browser, Statistik/Einstellungen/Training ohne Laufzeitfehler. Fix: SnackBar „Im Raum …“ verdeckte Double/Triple
- [x] Tutorial / Einführung / Changelog 3.0.0
- [x] APK\Darts_3.0.0.apk gebaut und signiert – [ ] Installation auf S24/Tablet (wartet auf Simon: Gerät anstecken)
- [x] release\darts_server_3.0.0.zip (ohne Schlüssel geprüft)
- [ ] iPhone-Test (wartet auf Simon: Leihgerät + Freigabe für cloudflared-Tunnel; Checkliste docs/ios_testliste.md)
- [x] Commit, Memory

Zusätzlich in 3.0.0: Eis-Logo, Statistik nach letztem Spiel sortiert, Gerätename iPhone/Browser im Web.

**Alles, was ohne Simon geht, ist erledigt.** Offen nur: Geräte-Installation, iPhone-Test, Server-Art/Domain des Freundes (→ defaultServerUrl in lib/net/server_config.dart eintragen, APK neu bauen).

## Notizen für Phase 3
- docs/lokaler_test.md: Menüpfad „Koppeln → Erweitert → Server-Adresse“ an echte UI von Agent C anpassen.
- Docker/systemd/Caddy/nginx nicht praktisch getestet (keine Linux-Umgebung hier).

- Nach Merge C prüfen: Fehler beim Öffnen von „Handys koppeln“ im Browser (2× Uncaught Error laut Agent B – vermutlich WLAN-Suche).
- Einstellungen im Browser: Raum-Code und „Spieler teilen … an anderes Handy“ sind WLAN-bezogen → im Web anpassen/ausblenden.
- Update im Web: Plat.I.reload() von Agent B nutzen.
- Prüfen, dass Roboto-Alias das Nachladen von fonts.gstatic.com verhindert (im Browser-Test).
- `pub get` in packages/darts_protocol, server, tool/e2e vor analyze.

## Bitte prüfen (Entscheidungen, die ich allein getroffen habe)
- Online-Raum-Codes sind 6-stellig (z. B. „K7M 2QX“) und werden vom Server vergeben – der 4-stellige WLAN-Code wäre online zu leicht zu erraten bzw. würde zwischen verschiedenen Nutzern kollidieren. Neue Geräte müssen weiterhin am Host bestätigt werden.
- „Kurz zwischenspeichern“ umgesetzt als: Raum + Code bleiben 24 h gültig (nur Metadaten im RAM); Spielstände/Namen speichert der Server NICHT – der Stand liegt auf dem Host-Gerät und wird nach Wiederverbindung neu verteilt. Datensparsamer bei gleichem Nutzen.
- Online kann jedes Gerät Host sein, auch ein iPhone im Browser.
