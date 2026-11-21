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
- [ ] B Web-Tauglichkeit
- [ ] C Kopplung in der App
- [x] D Paket, Anleitung, E2E-Tests – gemergt (7e8f2cd), E2E 9/9 grün gegen echten Server

## Phase 3 – Zusammenführen (allein)
- [ ] Merge aller Branches
- [ ] analyze + alle Tests + build web + build apk
- [ ] Lokaler Gesamttest vorbereitet (Server am PC, Geräte im WLAN)
- [ ] Tutorial / Einführung / Changelog 3.0.0
- [ ] APK\Darts_3.0.0.apk (+ adb install -r wenn angesteckt)
- [ ] release\darts_server_3.0.0.zip (ohne Schlüssel geprüft)
- [ ] iPhone-Test vorbereitet (cloudflared – vorher fragen!)
- [ ] Commit, Memory, Push

## Notizen für Phase 3
- docs/lokaler_test.md: Menüpfad „Koppeln → Erweitert → Server-Adresse“ an echte UI von Agent C anpassen.
- Docker/systemd/Caddy/nginx nicht praktisch getestet (keine Linux-Umgebung hier).

## Bitte prüfen (Entscheidungen, die ich allein getroffen habe)
- Online-Raum-Codes sind 6-stellig (z. B. „K7M 2QX“) und werden vom Server vergeben – der 4-stellige WLAN-Code wäre online zu leicht zu erraten bzw. würde zwischen verschiedenen Nutzern kollidieren. Neue Geräte müssen weiterhin am Host bestätigt werden.
- „Kurz zwischenspeichern“ umgesetzt als: Raum + Code bleiben 24 h gültig (nur Metadaten im RAM); Spielstände/Namen speichert der Server NICHT – der Stand liegt auf dem Host-Gerät und wird nach Wiederverbindung neu verteilt. Datensparsamer bei gleichem Nutzen.
- Online kann jedes Gerät Host sein, auch ein iPhone im Browser.
