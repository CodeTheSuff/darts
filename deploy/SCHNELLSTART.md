# Darts – Schnellstart (Docker)

Darts ist eine Web-App (für iPhone und Browser) und ein kleiner Vermittlungs-Server, damit
Handys online miteinander spielen können. Spielstände und Statistiken liegen **nur auf den
Geräten**, auf dem Server wird nichts gespeichert. Der Server braucht ungefähr 30–60 MB RAM.

## Was du brauchst

- einen Linux-Server mit **Docker** und **docker compose** (v2)
- eine **(Sub-)Domain**, z. B. `darts.deinedomain.de`, mit einem **A-Eintrag** auf die IP des Servers
- die **Ports 80 und 443** offen (Firewall bzw. Weiterleitung im Router) und nicht von einem
  anderen Webserver belegt. Läuft bei dir schon nginx, Traefik o. Ä., dann lies in
  `ANLEITUNG_HOSTING.md` den Weg **A2b**.

## Installieren (ca. 5 Minuten)

```bash
unzip darts_server_3.1.0.zip
cd darts_server_3.1.0
bash install.sh
```

Das Skript
1. prüft Docker, DNS und die Ports,
2. legt die Einstellungen `.env` an (die Domain ist schon eingetragen, sonst fragt es danach),
3. baut und startet die Container `darts` (Server) und `caddy` (HTTPS mit Let's-Encrypt-Zertifikat),
4. prüft am Ende `https://<deine-domain>/health`.

Bei „Fertig! Darts läuft unter https://…“ ist alles erledigt. Gib Simon kurz Bescheid.

## So kommen die Spieler zur App

- **Android:** auf dem Handy `https://<deine-domain>/app` öffnen → „Android-App herunterladen“ →
  installieren → zurück auf die Seite und „App mit diesem Server verbinden“ tippen.
  Damit ist die App fertig eingerichtet (Online-Spiel und Updates laufen über deinen Server).
- **iPhone/iPad/Computer:** `https://<deine-domain>` im Browser öffnen. Auf dem iPhone in Safari:
  Teilen → „Zum Home-Bildschirm“.

Neue Versionen: Simon schickt ein neues ZIP (siehe „Update“). Die Apps melden das Update dann von selbst.

## Danach

| Befehl | Wozu |
| --- | --- |
| `bash install.sh status` | Läuft alles? (Container + HTTPS-Prüfung) |
| `bash install.sh logs` | Logs ansehen (Strg+C beendet) |
| `bash install.sh stop` | anhalten |
| `bash install.sh` | wieder starten |

Die Container starten nach einem Neustart des Servers von selbst.

## Update

Simon schickt ein neues ZIP, z. B. `darts_server_3.0.1.zip`:

```bash
unzip darts_server_3.0.1.zip
cd darts_server_3.0.1
bash install.sh
```

Die Einstellungen aus dem alten Ordner werden automatisch übernommen, das Zertifikat bleibt
erhalten. Den alten Ordner kannst du danach löschen.

## Wenn etwas klemmt

- **„Port 80/443 schon belegt“**: Ein anderer Webserver läuft. Dann nach `ANLEITUNG_HOSTING.md`
  Weg A2b einrichten.
- **HTTPS antwortet nicht**: Meistens zeigt die Domain noch nicht auf den Server (DNS braucht
  manchmal bis zu einer Stunde), oder Port 80/443 ist nicht freigegeben.
  `bash install.sh logs` zeigt, was Caddy meldet.
- **„Kein Zugriff auf Docker“**: `sudo bash install.sh`

Mehr Details, ein Weg ohne Docker und alle Einstellungen stehen in `ANLEITUNG_HOSTING.md`.
