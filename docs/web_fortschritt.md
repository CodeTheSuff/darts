# Fortschritt Darts 3.0.0 (Web-App + Server)

Grundlage: `docs/PROMPT_WEB_UMZUG.md`, Architektur: `docs/web_architektur.md`.

## ⚠️ Offen (klären mit Simon / Freund)
- Server-Art des Freundes (Docker / Linux ohne Docker / Webspace?) und Domain mit HTTPS – Paket deckt Docker + systemd ab.
- Produktiv-Server-Adresse unbekannt → Platzhalter an einer Stelle.

## Phase 1 – Planung & Fundament (allein)
- [ ] Code der Kopplung gelesen (link.dart, link_coordinator.dart, link_screen.dart, sync.dart, storage.dart, error_log.dart)
- [ ] Probe-Build `flutter build web` + Fehlerliste
- [ ] docs/web_architektur.md (Protokoll, Transport, Zuständigkeiten, Tests)
- [ ] Gemeinsames Paket packages/darts_protocol + Ordner server/, deploy/
- [ ] Version 3.0.0
- [ ] Commit Phase 1

## Phase 2 – parallel (4 Agenten, Worktrees)
- [ ] A Server
- [ ] B Web-Tauglichkeit
- [ ] C Kopplung in der App
- [ ] D Paket, Anleitung, E2E-Tests

## Phase 3 – Zusammenführen (allein)
- [ ] Merge aller Branches
- [ ] analyze + alle Tests + build web + build apk
- [ ] Lokaler Gesamttest vorbereitet (Server am PC, Geräte im WLAN)
- [ ] Tutorial / Einführung / Changelog 3.0.0
- [ ] APK\Darts_3.0.0.apk (+ adb install -r wenn angesteckt)
- [ ] release\darts_server_3.0.0.zip (ohne Schlüssel geprüft)
- [ ] iPhone-Test vorbereitet (cloudflared – vorher fragen!)
- [ ] Commit, Memory, Push

## Bitte prüfen (Entscheidungen, die ich allein getroffen habe)
