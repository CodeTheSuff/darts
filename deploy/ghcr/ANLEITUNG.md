# Darts – Installation mit dem fertigen Image (ghcr.io)

Das Image wird bei jedem Release automatisch von GitHub Actions gebaut und unter
`ghcr.io/codethesuff/darts` veröffentlicht (Tags: `latest`, `X.Y`, `X.Y.Z`).
Es enthält den Vermittlungs-Server, die Web-App und die Android-App (für `/app` und das Selbst-Update).
Auf dem Server wird nichts gespeichert – Spielstände liegen nur auf den Geräten.

## Voraussetzungen

- Linux-Server mit Docker + `docker compose` (v2)
- (Sub-)Domain mit A-Eintrag auf den Server, Ports 80 und 443 frei und von außen erreichbar
  (läuft schon ein anderer Reverse-Proxy: siehe unten „Eigener Proxy“)
- Zugriff auf das private Repo → Token mit Recht **`read:packages`**
  (GitHub → Settings → Developer settings → Personal access tokens)

## Installieren

```bash
unzip darts-docker.zip && cd darts-docker
docker login ghcr.io -u <dein-github-name>      # Passwort = Token (read:packages)
bash install.sh darts.deinedomain.de
```

`install.sh` prüft Docker, DNS und Ports, legt `.env` an (Image-Adresse ist schon eingetragen),
lädt das Image, startet `darts` + `caddy` (Let's-Encrypt-Zertifikat) und prüft `https://<domain>/health`.

## Updates

```bash
bash install.sh update            # neueste Version holen und neu starten
bash install.sh autoupdate an     # jede Nacht 04:17 automatisch (Protokoll: update.log)
bash install.sh autoupdate aus
```

Die Android-Apps sehen die neue Version über `/version.json` und bieten den Download an,
die Web-App lädt neu. Eine bestimmte Version festhalten: in `.env`
`DARTS_IMAGE=ghcr.io/codethesuff/darts:3.1` (nur Bugfixes) oder `:3.1.0` (fest).

## Spieler einrichten

- **Android:** `https://<domain>/app` öffnen → App herunterladen → „App mit diesem Server verbinden“
- **iPhone/iPad/Computer:** `https://<domain>` im Browser (iPhone: Teilen → „Zum Home-Bildschirm“)

## Befehle

| Befehl | Wozu |
| --- | --- |
| `bash install.sh status` | Container + HTTPS-Prüfung |
| `bash install.sh logs` | Logs (Strg+C beendet) |
| `bash install.sh stop` | anhalten |

## Eigener Proxy (nginx, Traefik, NPM …)

Den `caddy`-Dienst in `docker-compose.yml` entfernen und `darts` stattdessen veröffentlichen, z. B.
`ports: ["127.0.0.1:8080:8080"]`. Der Proxy muss WebSockets auf `/ws` durchreichen und
`X-Forwarded-For`/`-Proto` setzen. Beispiel für nginx: `nginx-darts.conf` im Repo unter `deploy/`.

## Sicherheit

Container ohne Root-Rechte, nur lesbares Dateisystem, alle Capabilities entzogen, 256 MB Speichergrenze.
Von außen ist nur Caddy (HTTPS) erreichbar.
