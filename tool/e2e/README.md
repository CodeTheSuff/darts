# E2E-Test Vermittlungs-Server

Startet den echten Server aus `server/` und spielt mit **Host + 2 Gästen** als reine Protokoll-Clients
(WebSocket + `RelayFrame` aus `packages/darts_protocol`) ein kurzes Szenario durch:

1. HTTP: `/health`, `/version.json` (Format `VersionInfo`), `/apk/Darts_3.0.0.apk`, Web-App unter `/`, 404 für fehlende APK
2. Host öffnet Raum (`host` → `hosted`), 2 Gäste treten bei (`join` → `joined`, Host bekommt `peer+`)
3. Link-Nachrichten im Umschlag: Gast `hello` → Host `welcome` + `state` (per `to`, zielgenau), beim zweiten Gast vorher `pending`
4. `ping` → `pong`
5. X01 501 Double-Out bis zum Sieg: Gäste schicken `dart`/`undo`, der Host (Mini-Schiedsstelle im Test) verteilt `state` per `all`
6. Fehler: unbekannter Raum → `error noRoom`, Protokoll 2 → `error update`
7. Host trennt normal → Gäste `hostOffline`; falsches Token → `error token`; Zurückholen mit Token → `hosted resumed:true`, Gäste `hostOnline`
8. `kick` → Host bekommt `peer-`, gekickter Gast bekommt nichts mehr
9. Host schließt mit WebSocket-Close-Code **4000** → Gäste `closed`, Raum weg (`noRoom`)
10. Datenschutz: Namen, Geräte-IDs und Token stehen nicht in den Server-Logs (Server läuft dafür mit `LOG_LEVEL=debug`)

## Aufruf

```powershell
cd tool\e2e
C:\dev\flutter\bin\dart.bat pub get
C:\dev\flutter\bin\dart.bat test -r expanded
```

- Der Server wird mit `dart bin/server.dart` in `server/` gestartet (vorher `dart pub get` dort), auf einem freien Port,
  `HOST=127.0.0.1`, mit eigener Schein-Web-App, Schein-APK und `version.json` in einem Temp-Ordner.
- **Fehlt `server/bin/server.dart`, überspringt sich der Test** mit Hinweis (Stand Phase 2 in diesem Branch).
- `DARTS_SERVER_DIR=<pfad>` – anderen Server-Ordner nehmen.
- `DARTS_E2E_URL=https://darts.example.org` – gegen einen **laufenden** Server testen (z. B. nach dem Hosten beim Freund);
  dann entfallen die Prüfungen, die die Test-Dateien bzw. die Logs brauchen.

Der Test wurde in Phase 2 nur gegen ein Wegwerf-Mini-Relais nach `docs/web_architektur.md` geprüft (9/9 grün);
gegen den echten Server läuft er erst in Phase 3.
