# Darts-Server (Relais)

Kleiner Dart-Server für Darts 3.0. Er

- vermittelt Online-Spiele per Raum-Code (WebSocket-**Relais** unter `/ws` – er reicht die Link-Nachrichten
  der App nur weiter und versteht/speichert sie nicht),
- liefert die **Web-App** (Flutter-Web-Build) aus,
- liefert `/version.json` und die **APK** (`/apk/…`) für das Selbst-Update.

Gespeichert wird nur im Arbeitsspeicher und nur Metadaten (Raum-Code, SHA-256-Hash des Host-Tokens,
Zeitstempel, verbundene Peers). Keine Spielstände, keine Namen, nichts auf der Platte. Logs enthalten keine
Inhalte, keine IP-Adressen und Raum-Codes nur gekürzt (`K7…`).

Protokoll: `packages/darts_protocol` (`RelayFrame`), Gesamtbild: `docs/web_architektur.md`.

## Lokal starten

```sh
cd server
dart pub get
dart run bin/server.dart                         # Port 8080, Web-App aus ./web
WEB_DIR=../build/web PORT=9000 dart run bin/server.dart
dart run bin/server.dart --web-dir=../build/web --port=9000   # gleichwertig per Argument
dart run bin/server.dart --help
```

Kompilieren (eine Datei, ohne Dart-Installation lauffähig):

```sh
dart compile exe bin/server.dart -o build/darts_server
# Linux-Binary unter Windows (Dart ≥ 3.8):
dart compile exe --target-os=linux --target-arch=x64 bin/server.dart -o build/darts_server_linux_x64
```

Beenden mit Strg+C bzw. SIGTERM: alle WebSockets werden mit 1001 geschlossen (Räume gehen verloren; Hosts legen
sie danach mit demselben Code und Token neu an).

Tests: `dart test` · Analyse: `dart analyze`

## Umgebungsvariablen

| Variable | Standard | Bedeutung |
|---|---|---|
| `PORT` | `8080` | HTTP-Port |
| `HOST` | `0.0.0.0` | Bind-Adresse (`127.0.0.1` hinter einem Reverse-Proxy auf demselben Rechner) |
| `PUBLIC_URL` | leer | Öffentliche Adresse, z. B. `https://darts.example.org` – macht relative APK-Links in `error update` absolut |
| `WEB_DIR` | `./web` | Flutter-Web-Build (`build/web`) |
| `APK_DIR` | `./apk` | Ordner mit `Darts_<version>.apk` |
| `VERSION_FILE` | `./version.json` | Inhalt von `/version.json` (Format: `VersionInfo`) |
| `ROOM_TTL_HOURS` | `24` | Räume ohne Aktivität so lange behalten (Dezimalzahl erlaubt) |
| `MAX_ROOMS` | `500` | Höchstzahl Räume (danach `error busy`) |
| `MAX_PEERS_PER_ROOM` | `8` | Gäste je Raum (danach `error full`) |
| `MIN_PROTOCOL` | `3` | Ältere Clients bekommen `error update` |
| `TRUST_PROXY` | `false` | `true` nur hinter einem Reverse-Proxy: Client-IP = letzter Eintrag von `X-Forwarded-For` |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error`, `off` |

Ungültige Werte → Fehlermeldung und Exit-Code 64.

## Endpunkte

| Pfad | Antwort |
|---|---|
| `/ws` | WebSocket-Relais (ohne Upgrade: 426) |
| `/health` | `{"ok":true,"version":"3.0.0","rooms":…,"connections":…,"uptimeSeconds":…}` |
| `/version.json` | Inhalt von `VERSION_FILE`, `Cache-Control: no-cache`; 404 wenn nicht vorhanden |
| `/apk/<name>.apk` | Datei aus `APK_DIR` als `application/vnd.android.package-archive` (mit Range/ETag) |
| alles andere | Web-App aus `WEB_DIR`; `/` → `index.html`; Pfade ohne Dateiendung → `index.html` (SPA) |

`index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `manifest.json`, `version.json` und
`main.dart.{js,mjs,wasm}` (bei Flutter ohne Hash im Namen) kommen mit `no-cache` (ETag → meist nur 304),
alles andere mit `max-age=3600`. Immer gesetzt: `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
`X-Frame-Options: SAMEORIGIN`. Keine Verzeichnis-Listings, keine versteckten Dateien, Pfad-Traversal wird abgewiesen.
Nur `GET`/`HEAD` (sonst 405). `/health` und `/version.json` erlauben CORS (`*`).

## Relais-Verhalten (Kurzfassung)

- Erster Frame muss `host` oder `join` sein (sonst `error bad`), innerhalb von 10 s (sonst Trennung 4003).
- `proto` fehlt oder `< MIN_PROTOCOL` → `error update` mit `update: {version, apk}` aus `VERSION_FILE`, dann Trennung.
- `host` ohne `room` → neuer Raum + Token. `host` mit `room`+`token` → zurückholen (`resumed:true`); der Host
  bekommt danach für jeden schon verbundenen Gast ein `peer+`, die Gäste bekommen `hostOnline`.
  Unbekannter, aber gültiger Code → Raum mit diesem Code und Token neu anlegen (`resumed:false`).
  Falsches Token → `error token`. Eine neue Host-Verbindung ersetzt die alte (alte wird mit 4001 getrennt).
- `join` → Gast-ID `p1`, `p2`, … (je Raum fortlaufend, nie wiederverwendet), Host bekommt `peer+`.
- Host trennt normal → Gäste bekommen `hostOffline`, Raum bleibt. Host schließt mit Close-Code **4000** →
  Raum sofort gelöscht, Gäste bekommen `closed` und werden getrennt.
- Nachrichten eines Gasts, während der Host offline ist, werden verworfen.
- Unerwartete, aber lesbare Frames → `error bad`, Verbindung bleibt. Kaputtes JSON, Binär-Frames,
  zu große Frames (> 4 MB) → `error bad` und Trennung. Noch viel größere Nachrichten werden schon beim Empfang
  (vor dem vollständigen Puffern) hart abgebrochen.
- Rate-Limit je Verbindung (Token-Bucket 40/s, Spitze 200) → `error rate` und Trennung.
- Zehn falsche Raum-Codes (oder Host-Tokens) je IP (IPv6: je /64) → 10 min `error rate` für `join`/Zurückholen.
- Keine Aktivität 45 s → Trennung (4003). Clients senden alle 15 s `ping`.
- Kompression (permessage-deflate) wird bewusst nicht ausgehandelt.

Close-Codes des Servers: 1000 Raum geschlossen · 1001 Server fährt herunter · 1008 nach `error` ·
4001 Host ersetzt · 4002 vom Host entfernt (`kick`) · 4003 Zeitüberschreitung. Vom Host gesendet: 4000 Raum schließen.
