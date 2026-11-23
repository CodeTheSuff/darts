#!/usr/bin/env bash
# Darts – Installation und Update mit Docker + Caddy (automatisches HTTPS).
#
#   bash install.sh                 installieren bzw. aktualisieren (fragt bei Bedarf nach der Domain)
#   bash install.sh darts.beispiel.de   Domain direkt angeben
#   bash install.sh status          Zustand der Container + Prüfung
#   bash install.sh logs            Logs ansehen (Strg+C beendet)
#   bash install.sh stop            Darts anhalten (Einstellungen und Zertifikate bleiben)
#   bash install.sh update          nur ghcr.io-Weg: neueste Version holen und neu starten
#   bash install.sh autoupdate an   nur ghcr.io-Weg: jede Nacht (04:17) automatisch updaten (aus: … aus)
#
# Zwei Wege, automatisch erkannt:
#   ZIP-Weg    (bin/darts_server liegt daneben)  -> Image wird hier gebaut
#   ghcr.io-Weg (nur docker-compose.yml + Caddyfile) -> fertiges Image wird geladen
#
# Voraussetzungen: Linux-Server mit Docker + "docker compose" (v2), Domain zeigt per DNS auf den
# Server, Ports 80 und 443 sind von außen erreichbar und nicht von einem anderen Programm belegt.

set -euo pipefail

cd "$(dirname "$0")"

ROT=$'\033[31m'; GRUEN=$'\033[32m'; GELB=$'\033[33m'; FETT=$'\033[1m'; AUS=$'\033[0m'
if [ ! -t 1 ]; then ROT=''; GRUEN=''; GELB=''; FETT=''; AUS=''; fi

schritt() { printf '\n%s==> %s%s\n' "$FETT" "$1" "$AUS"; }
ok()      { printf '%s  ✓ %s%s\n' "$GRUEN" "$1" "$AUS"; }
warn()    { printf '%s  ! %s%s\n' "$GELB" "$1" "$AUS"; }
fehler()  { printf '%s  ✗ %s%s\n' "$ROT" "$1" "$AUS" >&2; exit 1; }

PLATZHALTER='darts.example.org'

# ------------------------------------------------------------------ Hilfen
env_wert() { # env_wert NAME -> Wert aus .env (leer, wenn nicht da)
  [ -f .env ] || return 0
  sed -n "s/^$1=//p" .env | tail -n 1 | tr -d '\r'
}

# ZIP-Weg: Server-Datei liegt bei; sonst fertiges Image von ghcr.io
if [ -e bin/darts_server ]; then MODUS=zip; else MODUS=image; fi

compose() {
  if [ "$MODUS" = zip ]; then docker compose --profile https "$@"; else docker compose "$@"; fi
}

ist_lokal() { case "$1" in localhost|*.localhost) return 0 ;; *) return 1 ;; esac; }

pruefe_docker() {
  schritt 'Docker prüfen'
  command -v docker >/dev/null 2>&1 || fehler 'Docker ist nicht installiert (https://docs.docker.com/engine/install/).'
  docker compose version >/dev/null 2>&1 || fehler '"docker compose" (v2) fehlt – Paket docker-compose-plugin installieren.'
  if ! docker info >/dev/null 2>&1; then
    fehler 'Kein Zugriff auf Docker. Mit sudo starten (sudo bash install.sh) oder Benutzer in die Gruppe "docker" aufnehmen.'
  fi
  ok "$(docker --version)"
  ok "$(docker compose version)"
}

pruefe_dateien() {
  local liste
  if [ "$MODUS" = zip ]; then
    liste='Dockerfile docker-compose.yml Caddyfile .env.example bin/darts_server web/index.html version.json'
  else
    liste='docker-compose.yml Caddyfile .env.example'
  fi
  for f in $liste; do
    [ -e "$f" ] || fehler "Datei fehlt: $f – install.sh im Ordner mit docker-compose.yml starten."
  done
}

# ghcr.io-Weg: Image-Adresse muss in .env stehen
pruefe_image() {
  [ "$MODUS" = image ] || return 0
  local img
  img="$(env_wert DARTS_IMAGE)"
  if [ -z "$img" ] || printf '%s' "$img" | grep -q 'OWNER'; then
    fehler 'In .env fehlt DARTS_IMAGE (z. B. DARTS_IMAGE=ghcr.io/<github-name>/darts:latest).'
  fi
  ok "Image: $img"
}

# Neues Image laden – bei privatem Repo vorher einmal bei ghcr.io anmelden.
lade_image() {
  if ! compose pull darts; then
    warn 'Image konnte nicht geladen werden. Bei einem privaten Repo einmal anmelden:'
    warn '  docker login ghcr.io -u <github-name>     (Passwort = Token mit Recht "read:packages")'
    fehler 'Laden fehlgeschlagen.'
  fi
}

# Holt Einstellungen aus einer älteren Version (Nachbarordner darts_server_*), falls hier keine .env liegt.
uebernimm_alte_env() {
  [ -f .env ] && return 0
  local hier alt laufend
  hier="$(pwd -P)"
  # 1. Ordner der laufenden Darts-Installation (Docker merkt sich ihn) – egal, wo das neue ZIP liegt.
  laufend="$(docker ps -q --filter label=com.docker.compose.project=darts --filter label=com.docker.compose.service=darts 2>/dev/null | head -n1 || true)"
  if [ -n "$laufend" ]; then
    alt="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$laufend" 2>/dev/null || true)"
    if [ -n "$alt" ] && [ -f "$alt/.env" ] && [ "$(cd "$alt" && pwd -P)" != "$hier" ]; then
      cp "$alt/.env" .env
      ok "Einstellungen übernommen aus $alt/.env"
      return 0
    fi
  fi
  # 2. Sonst der neueste Nachbarordner darts_server_*.
  alt="$(ls -1dt ../darts_server_*/.env 2>/dev/null | while read -r e; do
           [ "$(cd "$(dirname "$e")" && pwd -P)" = "$hier" ] || { echo "$e"; break; }
         done || true)"
  if [ -n "$alt" ]; then
    cp "$alt" .env
    ok "Einstellungen übernommen aus $alt"
  fi
}

richte_env_ein() {
  schritt 'Einstellungen (.env)'
  uebernimm_alte_env
  if [ ! -f .env ]; then
    cp .env.example .env
    ok '.env aus .env.example angelegt'
  fi
  local domain="${1:-}"
  [ -n "$domain" ] || domain="$(env_wert DOMAIN)"
  if [ -z "$domain" ] || [ "$domain" = "$PLATZHALTER" ]; then
    if [ -t 0 ]; then
      read -r -p '  Unter welcher Domain soll Darts laufen (z. B. darts.beispiel.de)? ' domain
    else
      fehler 'Keine Domain angegeben: bash install.sh darts.beispiel.de'
    fi
  fi
  domain="$(printf '%s' "$domain" | tr 'A-Z' 'a-z' | sed -e 's#^https\?://##' -e 's#/*$##')"
  printf '%s' "$domain" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$' \
    || fehler "Ungültige Domain: $domain"
  [ "$domain" != "$PLATZHALTER" ] || fehler 'Bitte die echte Domain angeben, nicht das Beispiel.'
  sed -i -e "s#^DOMAIN=.*#DOMAIN=$domain#" -e "s#^PUBLIC_URL=.*#PUBLIC_URL=https://$domain#" .env
  grep -q '^DOMAIN=' .env || printf 'DOMAIN=%s\n' "$domain" >> .env
  grep -q '^PUBLIC_URL=' .env || printf 'PUBLIC_URL=https://%s\n' "$domain" >> .env
  chmod 600 .env
  DOMAIN="$domain"
  ok "Domain: $DOMAIN"
}

pruefe_dns() {
  schritt 'DNS prüfen'
  if ist_lokal "$DOMAIN"; then ok "$DOMAIN ist lokal (Test) – Caddy nimmt ein eigenes Test-Zertifikat"; return 0; fi
  local ips
  ips="$( { getent ahosts "$DOMAIN" 2>/dev/null || true; } | awk '{print $1}' | sort -u | tr '\n' ' ')"
  if [ -z "$ips" ]; then
    warn "$DOMAIN lässt sich (noch) nicht auflösen. Beim Domain-Anbieter einen A-Eintrag auf die IP dieses Servers setzen."
    warn 'Ohne gültigen DNS-Eintrag bekommt Caddy kein HTTPS-Zertifikat.'
  else
    ok "$DOMAIN zeigt auf: $ips"
    echo '    (Muss die öffentliche IP dieses Servers sein.)'
  fi
}

pruefe_ports() {
  schritt 'Ports 80 und 443 prüfen'
  if [ -n "$(compose ps -q caddy 2>/dev/null)" ]; then ok 'Darts-Caddy läuft bereits (Update)'; return 0; fi
  if ! command -v ss >/dev/null 2>&1; then warn '"ss" fehlt – Ports nicht geprüft'; return 0; fi
  local belegt=''
  for p in 80 443; do
    if ss -Hltn "sport = :$p" 2>/dev/null | grep -q .; then belegt="$belegt $p"; fi
  done
  if [ -n "$belegt" ]; then
    fehler "Port(s)$belegt schon belegt (läuft ein anderer Webserver?). Dann Weg A2b in ANLEITUNG_HOSTING.md nehmen."
  fi
  ok 'frei'
}

starte() {
  if [ "$MODUS" = zip ]; then
    schritt 'Darts bauen und starten (dauert beim ersten Mal 1–2 Minuten)'
    chmod 0755 bin/darts_server 2>/dev/null || true
    compose up -d --build --remove-orphans
  else
    schritt 'Darts laden und starten'
    lade_image
    compose up -d --remove-orphans
  fi
}

# Nächtliches Update per crontab (nur ghcr.io-Weg)
autoupdate() {
  [ "$MODUS" = image ] || fehler 'Automatische Updates gibt es nur beim ghcr.io-Weg (fertiges Image).'
  command -v crontab >/dev/null 2>&1 || fehler '"crontab" fehlt (Paket cron installieren).'
  local hier zeile
  hier="$(pwd -P)"
  zeile="17 4 * * * cd '$hier' && bash install.sh update >> '$hier/update.log' 2>&1 # darts-autoupdate"
  case "${1:-}" in
    an|on)
      { crontab -l 2>/dev/null | grep -v '# darts-autoupdate' || true; echo "$zeile"; } | crontab -
      ok 'Automatische Updates an: jede Nacht um 04:17 (Protokoll: update.log)' ;;
    aus|off)
      { crontab -l 2>/dev/null | grep -v '# darts-autoupdate' || true; } | crontab -
      ok 'Automatische Updates aus' ;;
    *)
      if crontab -l 2>/dev/null | grep -q '# darts-autoupdate'; then ok 'Automatische Updates: an'; else ok 'Automatische Updates: aus'; fi ;;
  esac
}

warte_gesund() {
  schritt 'Warten, bis Darts bereit ist'
  local id status i
  id="$(compose ps -q darts)"
  [ -n "$id" ] || fehler 'Container "darts" läuft nicht – Logs: bash install.sh logs'
  for i in $(seq 1 30); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || echo '?')"
    case "$status" in
      healthy) ok 'Server läuft (Healthcheck ok)'; return 0 ;;
      unhealthy|exited|dead) break ;;
    esac
    sleep 2
  done
  compose logs --tail 40 darts >&2 || true
  fehler "Server meldet sich nicht gesund (Status: $status)."
}

pruefe_https() {
  schritt "HTTPS prüfen: https://$DOMAIN"
  command -v curl >/dev/null 2>&1 || { warn 'curl fehlt – bitte https://'"$DOMAIN"'/health im Browser öffnen'; return 0; }
  local opt=() i
  if ist_lokal "$DOMAIN"; then opt=(-k --resolve "$DOMAIN:443:127.0.0.1"); fi
  # Beim ersten Start holt Caddy das Zertifikat – das kann bis zu einer Minute dauern.
  for i in $(seq 1 30); do
    if curl -fsS --max-time 8 ${opt[@]+"${opt[@]}"} "https://$DOMAIN/health" >/dev/null 2>&1; then
      ok "https://$DOMAIN/health antwortet"
      if curl -fsS --max-time 8 ${opt[@]+"${opt[@]}"} "https://$DOMAIN/version.json" 2>/dev/null | grep -q '"version"'; then
        ok "Version: $(curl -fsS --max-time 8 ${opt[@]+"${opt[@]}"} "https://$DOMAIN/version.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n1)"
      fi
      return 0
    fi
    sleep 3
  done
  warn "https://$DOMAIN antwortet noch nicht. Häufigste Gründe: DNS zeigt noch nicht auf diesen Server,"
  warn 'Ports 80/443 sind in der Firewall bzw. im Router nicht freigegeben. Caddy-Logs:'
  compose logs --tail 30 caddy >&2 || true
  return 1
}

# ------------------------------------------------------------------ Befehle
case "${1:-}" in
  status)
    pruefe_docker
    DOMAIN="$(env_wert DOMAIN)"
    schritt 'Container'
    compose ps
    [ -n "$DOMAIN" ] && pruefe_https
    exit 0 ;;
  logs)
    compose logs -f --tail 100
    exit 0 ;;
  stop)
    compose down
    ok 'Darts angehalten. Neu starten: bash install.sh'
    exit 0 ;;
  update)
    [ "$MODUS" = image ] || fehler 'Beim ZIP-Weg: neues ZIP daneben entpacken und dort "bash install.sh" starten.'
    pruefe_docker
    DOMAIN="$(env_wert DOMAIN)"
    pruefe_image
    schritt 'Neueste Version laden'
    alt="$(docker inspect -f '{{.Image}}' "$(compose ps -q darts 2>/dev/null)" 2>/dev/null || true)"
    lade_image
    compose up -d --remove-orphans
    warte_gesund
    neu="$(docker inspect -f '{{.Image}}' "$(compose ps -q darts)" 2>/dev/null || true)"
    if [ -n "$alt" ] && [ "$alt" = "$neu" ]; then ok 'Schon die neueste Version'; else ok 'Aktualisiert'; docker image prune -f >/dev/null 2>&1 || true; fi
    [ -n "$DOMAIN" ] && pruefe_https
    exit 0 ;;
  autoupdate)
    autoupdate "${2:-}"
    exit 0 ;;
  -h|--help|hilfe)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

pruefe_dateien
pruefe_docker
richte_env_ein "${1:-}"
pruefe_image
pruefe_dns
pruefe_ports
starte
warte_gesund
if pruefe_https; then
  printf '\n%sFertig! Darts läuft unter https://%s%s\n' "$GRUEN$FETT" "$DOMAIN" "$AUS"
  echo
  printf '  %sAndroid:%s auf dem Handy https://%s/app öffnen → App herunterladen,\n' "$FETT" "$AUS" "$DOMAIN"
  echo '           danach „App mit diesem Server verbinden“ tippen. Fertig.'
  printf '  %siPhone:%s  https://%s in Safari öffnen → Teilen → „Zum Home-Bildschirm“.\n' "$FETT" "$AUS" "$DOMAIN"
  if command -v qrencode >/dev/null 2>&1; then
    echo
    echo '  QR-Code für Android (mit der Handy-Kamera scannen):'
    qrencode -t ANSIUTF8 -m 2 "https://$DOMAIN/app" | sed 's/^/    /'
  fi
  echo
  if [ "$MODUS" = zip ]; then
    echo '  Update später: neues ZIP daneben entpacken und dort wieder "bash install.sh" starten.'
  else
    echo '  Update später: "bash install.sh update" – oder automatisch: "bash install.sh autoupdate an".'
  fi
else
  printf '\n%sDarts läuft, aber HTTPS ist noch nicht erreichbar – siehe Hinweise oben.%s\n' "$GELB" "$AUS"
  echo '  Wenn DNS/Ports korrigiert sind: bash install.sh status'
  exit 1
fi
