# Darts – Anleitung zum Hosten

> **Was ich von dir brauche** (bitte kurz an Simon zurückmelden, bevor du loslegst)
>
> 1. **Welche Art Server?**
>    - Linux-Server/VPS (x86-64) mit Root-Zugang – **mit Docker** oder **ohne Docker**?
>    - oder ein NAS (welches, mit Docker/Container Manager?)
>    - oder nur Webspace (Hosting-Paket ohne eigene Programme)? → siehe Abschnitt [Nur Webspace oder NAS](#11-nur-webspace-oder-nas)
> 2. **Welche Adresse?** Eine (Sub-)Domain wie `darts.deinedomain.de`, deren DNS auf den Server zeigt.
> 3. **HTTPS:** Läuft dort schon ein Webserver/Reverse-Proxy (nginx, Caddy, Traefik, Apache …) oder sind Port 80 und 443 frei?
> 4. Läuft die Domain über **Cloudflare** (oranges Wölkchen)?
>
> Die Adresse (Punkt 2) trägt Simon fest in die Android-App ein.

---

## Inhalt

1. [Was ist das?](#1-was-ist-das)
2. [Voraussetzungen](#2-voraussetzungen)
3. [Inhalt des ZIP](#3-inhalt-des-zip)
4. [Weg A – mit Docker](#4-weg-a--mit-docker)
5. [Weg B – ohne Docker (systemd)](#5-weg-b--ohne-docker-systemd)
6. [Prüfen, ob alles läuft](#6-prüfen-ob-alles-läuft)
7. [Update mit neuem ZIP](#7-update-mit-neuem-zip)
8. [Logs und Ressourcen](#8-logs-und-ressourcen)
9. [Datenschutz und Sicherheit](#9-datenschutz-und-sicherheit)
10. [Fehlerbehebung / FAQ](#10-fehlerbehebung--faq)
11. [Nur Webspace oder NAS](#11-nur-webspace-oder-nas)
12. [Einstellungen (Referenz)](#12-einstellungen-referenz)

---

## 1. Was ist das?

**Darts** ist eine Punktezähler-App (X01, Training, Minispiele, Turniere). Das Paket enthält:

- die **Web-App** (für iPhone/iPad und jeden Browser, als „App“ auf dem Home-Bildschirm nutzbar),
- einen kleinen **Vermittlungs-Server** (eine einzige Programmdatei, geschrieben in Dart). Er
  - liefert die Web-App aus,
  - vermittelt Spiele zwischen Geräten per **Raum-Code** (WebSocket unter `/ws`) – er reicht Nachrichten nur weiter,
  - stellt `/version.json` und die aktuelle Android-APK unter `/apk/…` für das Selbst-Update bereit,
  - meldet unter `/health`, dass er läuft.

Es gibt **keine Datenbank**, **keine Konten**, **keine Dateien**, die geschrieben werden. Alles, was der Server weiß,
liegt im Arbeitsspeicher und ist nach einem Neustart weg (das ist gewollt).

```
Browser / iPhone ─┐                         ┌───────────────────────────────┐
Android-App ──────┼── https / wss ──► Proxy ─┤ darts_server  (Port 8080)     │
Android-App ──────┘    (443)        (Caddy/  │  /      Web-App               │
                                     nginx)  │  /ws    Relais (WebSocket)    │
                                             │  /health, /version.json, /apk │
                                             └───────────────────────────────┘
```

## 2. Voraussetzungen

| Was | Details |
|---|---|
| Server | Linux **x86-64** (amd64), z. B. Debian 12/13, Ubuntu 22.04/24.04. ARM (Raspberry Pi, manche NAS) geht mit der beiliegenden Datei **nicht** – siehe [FAQ](#10-fehlerbehebung--faq). |
| Arbeitsspeicher | ca. **50–100 MB** im Betrieb (Grenze im Paket: 256 MB) |
| Festplatte | ca. **250 MB** (davon APK ~80 MB, Web-App ~60 MB; mit Docker-Image ~350 MB) |
| CPU | minimal (ein kleiner vServer reicht locker) |
| Netz | Ports **80** und **443** von außen erreichbar (80 nur für das Let's-Encrypt-Zertifikat und die Umleitung) |
| Domain | eine **(Sub-)Domain** mit DNS-Eintrag (A und ggf. AAAA) auf den Server |
| HTTPS | **Pflicht.** Ohne HTTPS funktionieren auf dem iPhone „Zum Home-Bildschirm“, Offline-Start, Bildschirm-wach-halten und Speicher-Schutz nicht, und Browser blockieren unsichere WebSockets. |
| Software | **Weg A:** Docker + Docker Compose v2 (`docker compose …`). **Weg B:** systemd und nginx oder Caddy. Flutter/Dart wird **nicht** gebraucht. |

## 3. Inhalt des ZIP

```
darts_server_<version>/
├── bin/darts_server         Server (Linux x64, fertig kompiliert)
├── web/                     Web-App (statische Dateien)
├── apk/Darts_<version>.apk  Android-App für das Selbst-Update
├── version.json             aktuelle Version + Änderungsliste
├── Dockerfile               Laufzeit-Image (Weg A)
├── docker-compose.yml       Dienst "darts" + optionaler Caddy (Weg A)
├── .dockerignore
├── Caddyfile                Caddy mit automatischem HTTPS (Weg A und B)
├── nginx-darts.conf         nginx-Beispiel (Weg B oder eigener Proxy)
├── darts.service            systemd-Dienst (Weg B)
├── .env.example             alle Einstellungen mit Erklärung
├── install.sh               Installation/Update mit Docker + Caddy in einem Schritt
├── SCHNELLSTART.md          Kurzanleitung (Docker)
└── ANLEITUNG_HOSTING.md     diese Anleitung
```

Hochladen z. B. mit `scp darts_server_<version>.zip benutzer@server:~` und dort `unzip darts_server_<version>.zip`.

> Hinweis: Das ZIP wurde unter Windows gepackt. Das Ausführungsrecht der Server-Datei geht dabei evtl. verloren –
> bei Weg B deshalb `chmod +x bin/darts_server` (steht unten in den Schritten). Bei Docker erledigt das das Dockerfile.

---

## 4. Weg A – mit Docker

Das Image wird **auf dem Server** aus den fertigen Dateien gebaut (dauert Sekunden, es wird nichts kompiliert).
Basis ist `debian:stable-slim`, der Dienst läuft als Nicht-root-Benutzer, nur lesend, ohne Zusatzrechte.

### Kurzweg: `install.sh` (empfohlen für den mitgelieferten Caddy)

```bash
unzip darts_server_<version>.zip
cd darts_server_<version>
bash install.sh            # oder: bash install.sh darts.deinedomain.de
```

Das Skript erledigt A1 und A2a in einem Rutsch: prüft Docker, DNS und Ports 80/443, legt `.env` an,
startet die Container und prüft am Ende `https://<domain>/health`. Bei einem Update übernimmt es die
`.env` aus dem älteren Ordner `darts_server_*` daneben. Weitere Befehle: `bash install.sh status | logs | stop`.
Kurzfassung für alles: `SCHNELLSTART.md`. Die Schritte A1–A2a unten sind dasselbe von Hand.

### A1. Vorbereiten

```bash
sudo mkdir -p /opt/darts
sudo unzip darts_server_<version>.zip -d /opt/darts/
cd /opt/darts/darts_server_<version>
cp .env.example .env
nano .env        # DOMAIN und PUBLIC_URL auf deine (Sub-)Domain setzen
```

### A2a. Ohne eigenen Webserver – mitgelieferter Caddy macht HTTPS automatisch

Voraussetzung: Port 80 und 443 sind frei, DNS zeigt schon auf den Server.

```bash
docker compose --profile https up -d --build
docker compose --profile https logs -f caddy      # Zertifikat wird geholt (dauert ~10–30 s)
```

Fertig – `https://<deine-domain>` aufrufen. Die Zertifikate liegen im Docker-Volume `darts_caddy_data`
und werden automatisch erneuert.

### A2b. Mit vorhandenem Reverse-Proxy (nginx, Traefik, Caddy, Apache, Nginx Proxy Manager …)

```bash
docker compose up -d --build
curl http://127.0.0.1:8080/health     # → HTTP 200
```

Der Container ist nur unter `127.0.0.1:8080` erreichbar (anderer Port: `DARTS_HOST_PORT` in `.env`).
Den Proxy auf `http://127.0.0.1:8080` zeigen lassen; **WebSocket für `/ws` muss erlaubt sein**:

- **nginx:** Vorlage `nginx-darts.conf` (Abschnitt `location /ws` mit `Upgrade`/`Connection`-Headern und langem `proxy_read_timeout`).
- **Caddy:** `reverse_proxy 127.0.0.1:8080` genügt, WebSockets gehen automatisch (siehe `Caddyfile`).
- **Nginx Proxy Manager:** beim Proxy-Host „Websockets Support“ einschalten.
- **Traefik:** WebSockets gehen automatisch; Router auf den Dienst `darts` (Port 8080) – dann am besten den
  `ports:`-Eintrag in `docker-compose.yml` durch Traefik-Labels ersetzen.
- **Apache:** `mod_proxy_wstunnel`, z. B. `ProxyPass /ws ws://127.0.0.1:8080/ws` vor `ProxyPass / http://127.0.0.1:8080/`.

Läuft der Proxy selbst in Docker (eigenes Netz), statt des Port-Eintrags den Container `darts` mit ins Proxy-Netz hängen
und dort `http://darts:8080` als Ziel nehmen.

### A3. Nützliche Befehle

```bash
docker compose ps                    # Status (inkl. "healthy")
docker compose logs -f darts         # Logs
docker compose restart darts
docker compose down                  # stoppen (bei A2a: --profile https mit angeben)
```

---

## 5. Weg B – ohne Docker (systemd)

### B1. Benutzer und Dateien

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin darts
sudo mkdir -p /opt/darts /etc/darts
unzip darts_server_<version>.zip
sudo cp -r darts_server_<version>/. /opt/darts/
sudo chmod +x /opt/darts/bin/darts_server
sudo chown -R root:root /opt/darts
sudo chmod -R a+rX /opt/darts
```

Der Dienst-Benutzer `darts` darf die Dateien nur **lesen**.

### B2. Einstellungen

```bash
sudo cp /opt/darts/.env.example /etc/darts/darts.env
sudo nano /etc/darts/darts.env     # PUBLIC_URL setzen; HOST=127.0.0.1, TRUST_PROXY=true lassen
sudo chmod 640 /etc/darts/darts.env
sudo chown root:darts /etc/darts/darts.env
```

### B3. Dienst einrichten

```bash
sudo cp /opt/darts/darts.service /etc/systemd/system/darts.service
sudo systemctl daemon-reload
sudo systemctl enable --now darts
systemctl status darts
curl http://127.0.0.1:8080/health  # → HTTP 200
```

Der Dienst ist gehärtet (`NoNewPrivileges`, `ProtectSystem=strict`, eigener Benutzer, keine Capabilities,
Speichergrenze 256 MB) und startet bei Absturz automatisch neu.

### B4. HTTPS davor

**Variante Caddy** (einfachste – holt und erneuert das Zertifikat selbst):

```bash
sudo apt install caddy
sudo cp /opt/darts/Caddyfile /etc/caddy/Caddyfile
sudo nano /etc/caddy/Caddyfile     # {$DOMAIN} durch darts.deinedomain.de ersetzen
sudo systemctl reload caddy
```

(Hat Caddy schon andere Seiten, nur den Block `darts.deinedomain.de { … }` ergänzen.)

**Variante nginx + certbot:**

```bash
sudo cp /opt/darts/nginx-darts.conf /etc/nginx/sites-available/darts.conf
sudo sed -i 's/darts.example.org/darts.deinedomain.de/g' /etc/nginx/sites-available/darts.conf
sudo ln -s /etc/nginx/sites-available/darts.conf /etc/nginx/sites-enabled/
```

Falls noch kein Zertifikat da ist: in der Datei vorerst den `server { listen 443 … }`-Block auskommentieren,
`sudo nginx -t && sudo systemctl reload nginx`, dann `sudo certbot certonly --webroot -w /var/www/html -d darts.deinedomain.de`,
Block wieder einkommentieren, erneut `nginx -t` und `reload`.

---

## 5a. Spieler einrichten: Seite `/app`

Unter `https://<deine-domain>/app` liegt eine kleine Seite für die Spieler:

- **„Android-App herunterladen“** – die APK aus `apk/` (Version laut `version.json`)
- **„App mit diesem Server verbinden“** – öffnet die installierte App und trägt diesen Server ein
  (Link `darts://connect?server=…`; die App fragt vorher nach und prüft die Verbindung)
- **„Im Browser spielen“** – für iPhone, iPad und Computer

Die App braucht deshalb keine fest eingebaute Adresse – dasselbe Paket passt zu jedem Server.
Die Adresse auf der Seite kommt aus `PUBLIC_URL` (in `.env`, setzt `install.sh` automatisch).

## 6. Prüfen, ob alles läuft

```bash
curl -i https://darts.deinedomain.de/health          # HTTP 200
curl https://darts.deinedomain.de/version.json       # {"version":"…","build":…,"apk":"/apk/Darts_….apk",…}
curl -I https://darts.deinedomain.de/apk/Darts_<version>.apk   # HTTP 200, ca. 80 MB
```

WebSocket-Test (optional, z. B. mit `websocat` oder im Browser):
`wss://darts.deinedomain.de/ws` – nach dem Verbinden `{"r":"ping"}` senden → Antwort `{"r":"pong"}`.

Dann:

1. **Browser am PC:** `https://darts.deinedomain.de` – die App startet.
2. **Handy:** dieselbe Adresse öffnen; im iPhone-Safari „Teilen → Zum Home-Bildschirm“.
3. **Zusammen spielen:** Auf einem Gerät „Koppeln → Online → Raum öffnen“, das zweite Gerät gibt den Raum-Code ein.

## 7. Update mit neuem ZIP

Simon schickt bei jeder neuen Version ein neues ZIP. Laufende Räume gehen beim Neustart verloren
(die Geräte verbinden sich selbst neu, der Spielstand liegt auf dem Host-Gerät) – am besten also nicht mitten im Turnier.

### Docker (Weg A)

Mit dem mitgelieferten Caddy reicht: neues ZIP neben das alte entpacken, in den neuen Ordner wechseln,
`bash install.sh`. Von Hand:

```bash
cd /opt/darts
sudo unzip darts_server_<neu>.zip -d /opt/darts/
sudo cp darts_server_<alt>/.env darts_server_<neu>/.env
cd darts_server_<neu>
docker compose --profile https up -d --build     # bzw. ohne --profile https bei eigenem Proxy
docker compose ps
```

Weil der Projektname fest `darts` ist (`name:` in `docker-compose.yml`), ersetzt der neue Ordner die Container
des alten und übernimmt das Zertifikats-Volume – ein `down` vorher ist nicht nötig.
**Rollback:** in den alten Ordner wechseln und dort `docker compose --profile https up -d --build`.
Alte Ordner nach ein paar Tagen löschen.

### Ohne Docker (Weg B)

```bash
unzip darts_server_<neu>.zip
sudo systemctl stop darts
sudo mv /opt/darts /opt/darts.alt
sudo mkdir /opt/darts
sudo cp -r darts_server_<neu>/. /opt/darts/
sudo chmod +x /opt/darts/bin/darts_server
sudo chown -R root:root /opt/darts && sudo chmod -R a+rX /opt/darts
sudo systemctl start darts
curl http://127.0.0.1:8080/version.json
```

Nur wenn sich `darts.service` oder `.env.example` geändert haben (steht dann in Simons Nachricht): Datei
nach `/etc/systemd/system/` kopieren + `sudo systemctl daemon-reload` bzw. neue Einstellungen in `/etc/darts/darts.env` übernehmen.
**Rollback:** `sudo systemctl stop darts && sudo rm -rf /opt/darts && sudo mv /opt/darts.alt /opt/darts && sudo systemctl start darts`.

Die Android-Apps sehen die neue Version über `/version.json` und bieten den Download an; die Web-App zeigt
„Neue Version – neu laden“.

## 8. Logs und Ressourcen

| | Docker | systemd |
|---|---|---|
| Logs live | `docker compose logs -f darts` | `journalctl -u darts -f` |
| letzte Stunde | `docker compose logs --since 1h darts` | `journalctl -u darts --since "1 hour ago"` |
| Speicher/CPU | `docker stats darts-darts-1` | `systemctl status darts` (Zeile „Memory“) |

- Log-Umfang über `LOG_LEVEL` (`error`, `warn`, `info`, `debug`). Docker-Logs werden auf 3 × 10 MB begrenzt.
- Erwartet: wenige MB Speicher je Raum, insgesamt meist < 100 MB. Netzverkehr: ein paar KB je Wurf,
  plus einmalig die Web-App (bis ~60 MB, komprimiert deutlich weniger) bzw. APK (~80 MB) beim Laden/Update.

## 9. Datenschutz und Sicherheit

**Datenschutz**

- Keine Datenbank, keine Konten, keine Cookies, **nichts wird auf der Festplatte gespeichert**.
- Der Server kennt je Raum nur Raum-Code, einen Hash des Host-Tokens, Zeitstempel und welche Verbindungen gerade drin sind –
  ausschließlich im Arbeitsspeicher.
- Spielstände und Spielernamen werden nur **durchgereicht**, nicht gespeichert und **nicht geloggt**.
  Alle Spieldaten liegen auf den Geräten der Nutzer.
- Räume verfallen nach **24 Stunden** ohne Aktivität (`ROOM_TTL_HOURS`) oder sofort, wenn der Host den Raum schließt.
- In den Logs können IP-Adressen auftauchen (Fehler, Sperren) – wie bei jedem Webserver. Docker begrenzt die Log-Größe,
  bei systemd gilt die journald-Aufbewahrung des Servers.

**Sicherheit**

- Firewall: nach außen nur **22 (SSH), 80, 443** offen. Port 8080 **nicht** freigeben – der Server lauscht
  bei Weg A nur auf `127.0.0.1`, bei Weg B mit `HOST=127.0.0.1`.
  Beispiel `ufw`: `sudo ufw allow OpenSSH && sudo ufw allow 80,443/tcp && sudo ufw allow 443/udp && sudo ufw enable`.
- Achtung: Docker-Ports an `0.0.0.0` umgehen `ufw` – deshalb bindet `docker-compose.yml` den Dienst nur an `127.0.0.1`.
- Eingebaute Schutzmaßnahmen: Rate-Limit je Verbindung, Sperre je IP nach zu vielen falschen Raum-Codes,
  maximale Nachrichtengröße (4 MB), maximale Raumzahl (`MAX_ROOMS`) und Gäste je Raum, Zeitlimits.
  Ein Raum-Code allein reicht nicht – der Host muss jedes neue Gerät bestätigen.
- `TRUST_PROXY=true` nur, wenn der Server ausschließlich über den Proxy erreichbar ist (sonst könnte jemand
  seine IP im Header fälschen und die Sperre umgehen).
- Updates des Betriebssystems und von Docker/Caddy/nginx wie gewohnt einspielen.

## 10. Fehlerbehebung / FAQ

**Web-App lädt, aber „Online“ verbindet nicht / Raum öffnen hängt.**
Fast immer der WebSocket hinter dem Proxy. Prüfen:
- nginx: `proxy_http_version 1.1`, `Upgrade`- und `Connection`-Header im `location /ws`-Block (siehe Vorlage).
- `proxy_read_timeout` hoch (Vorlage: 3600 s) – sonst trennt nginx nach 60 s.
- Apache: `mod_proxy_wstunnel` aktiv? Nginx Proxy Manager: „Websockets Support“ an?
- Im Browser (F12 → Netzwerk → WS) muss `wss://…/ws` mit Status **101** erscheinen.

**Cloudflare-Proxy (oranges Wölkchen).**
Funktioniert. In Cloudflare unter *Network* „WebSockets“ eingeschaltet lassen (Standard), SSL-Modus **Full (strict)**.
`TRUST_PROXY=true` setzen. Cloudflare trennt WebSockets gelegentlich (z. B. bei eigenen Updates) – die App verbindet sich
selbst neu. Wenn Caddy das Zertifikat nicht bekommt: Wölkchen für die erste Ausstellung kurz grau schalten.

**Zertifikat wird nicht ausgestellt (Caddy/certbot).**
- DNS zeigt noch nicht (oder auf eine alte IP): `dig +short darts.deinedomain.de` prüfen.
- Port 80 von außen blockiert (Firewall des Anbieters / Router) – Let's Encrypt braucht ihn.
- Ein anderer Dienst belegt 80/443: `sudo ss -ltnp | grep -E ':80|:443'`.
- Zu viele Versuche → Let's Encrypt sperrt ~1 h. Logs: `docker compose --profile https logs caddy`.

**Zertifikatsfehler im Browser, obwohl alles stimmt.**
Uhrzeit prüfen – auf dem Server (`timedatectl`, NTP an?) und auf dem Handy. Eine falsche Uhr macht gültige Zertifikate „ungültig“.

**`exec format error` / „cannot execute binary file“.**
Der Server ist kein x86-64 (z. B. ARM-NAS, Raspberry Pi). Simon kann eine ARM64-Version bauen – Bescheid geben (`uname -m` nennen).

**`Permission denied` beim Start (Weg B).**
`sudo chmod +x /opt/darts/bin/darts_server`.

**`/health` geht, aber die App zeigt eine alte Version.**
Browser-Cache / Service Worker: Seite neu laden; auf dem iPhone die Home-Bildschirm-App einmal schließen und neu öffnen.
Prüfen, ob `/version.json` die neue Version zeigt (sonst läuft noch der alte Container/Ordner).

**Port 8080 schon belegt.**
Docker: `DARTS_HOST_PORT=8081` in `.env` und den Proxy auf 8081 zeigen lassen. Weg B: `PORT=8081` in `/etc/darts/darts.env`.

**Unterpfad statt eigener Subdomain (z. B. `deinedomain.de/darts/`).**
Geht nur mit einem speziell gebauten Web-Paket – eine eigene Subdomain ist deutlich einfacher. Sonst Simon fragen.

## 11. Nur Webspace oder NAS

**Reiner Webspace** (nur PHP/HTML hochladen, keine eigenen Dauer-Prozesse, kein Root): Der Vermittlungs-Server kann dort
**nicht** laufen – er muss dauerhaft als Prozess laufen und WebSockets annehmen. Möglichkeiten:

1. **Kleiner vServer dazu:** ein günstiger Linux-vServer (die kleinste Stufe gängiger Anbieter, wenige Euro im Monat,
   1 vCPU / 1 GB RAM reicht weit) und dort Weg A oder B. Eine Subdomain deiner Domain (z. B. `darts.deinedomain.de`)
   per DNS-A-Eintrag auf diesen Server zeigen lassen. **Empfohlen** – dann liegt alles an einem Ort.
2. **Aufteilen:** Web-App auf dem Webspace und nur den Server auf einem vServer/NAS. Das geht technisch, braucht aber
   ein extra gebautes Web-Paket mit der Server-Adresse und CORS-freundlichen Einstellungen – vorher mit Simon absprechen.
3. Ohne Server: Die Android-App koppelt weiterhin im **WLAN** ohne Internet; iPhones bleiben dann aber außen vor.

Bitte nichts buchen, ohne das mit Simon abzustimmen.

**NAS** (Synology, QNAP, Unraid, TrueNAS …):
- Mit Docker/Container Manager und **x86-64-CPU**: Weg A (Projekt aus `docker-compose.yml` anlegen).
  HTTPS über den eingebauten Reverse-Proxy des NAS (Synology: *Systemsteuerung → Anmeldeportal → Erweitert → Reverse-Proxy*,
  dort unter „Benutzerdefinierte Kopfzeile“ **WebSocket** hinzufügen) mit Ziel `http://localhost:8080`.
  Zertifikat über die Let's-Encrypt-Funktion des NAS. Router: Port 443 (und 80) zum NAS weiterleiten.
- Mit ARM-CPU: geht nur mit einer ARM-Version (siehe FAQ) – Simon fragen.
- Eine DynDNS-Adresse des NAS (z. B. `name.synology.me`) funktioniert als Domain.

## 12. Einstellungen (Referenz)

Alle Werte stehen kommentiert in `.env.example`.

| Variable | Standard | Bedeutung |
|---|---|---|
| `PORT` | `8080` | Port des Servers (Docker: fest 8080 im Container) |
| `HOST` | `0.0.0.0` | Adresse, auf der gelauscht wird; hinter Proxy auf demselben Rechner `127.0.0.1` |
| `PUBLIC_URL` | – | öffentliche Adresse, z. B. `https://darts.deinedomain.de` |
| `WEB_DIR` | `./web` | Ordner der Web-App |
| `APK_DIR` | `./apk` | Ordner mit der APK |
| `VERSION_FILE` | `./version.json` | Versionsdatei |
| `ROOM_TTL_HOURS` | `24` | Räume ohne Aktivität verfallen danach |
| `MAX_ROOMS` | `500` | höchstens so viele gleichzeitige Räume |
| `MAX_PEERS_PER_ROOM` | `8` | Gäste je Raum |
| `MIN_PROTOCOL` | `3` | ältere Apps bekommen „Bitte aktualisieren“ |
| `TRUST_PROXY` | `false` | `true` hinter Reverse-Proxy (Docker: fest `true`) |
| `LOG_LEVEL` | `info` | `error`, `warn`, `info`, `debug` |
| `DOMAIN` | – | nur Docker + Caddy: Domain für das Zertifikat |
| `DARTS_HOST_PORT` | `8080` | nur Docker: lokaler Port auf dem Server |

Endpunkte: `/` Web-App · `/ws` WebSocket-Relais · `/health` Lebenszeichen · `/version.json` · `/apk/<datei>.apk`.

Bei Fragen: Simon.
