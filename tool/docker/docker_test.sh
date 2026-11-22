#!/usr/bin/env bash
# Lokaler Docker-Test des Release-ZIP – spielt genau den Weg nach, den der Freund geht.
# Läuft in WSL (Ubuntu) als root, gestartet von tool/docker/docker_test.ps1.
#
#   bash docker_test.sh <zip> <phase>
#     phase = install   ZIP frisch entpacken, install.sh darts.localhost, alle Prüfungen
#     phase = update    zweites ZIP (Version +1) daneben, install.sh ohne Domain -> übernimmt .env
#     phase = restart   Container- und Docker-Neustart überstehen
#     phase = cleanup   alles wieder entfernen (Container, Volumes, Image, Testordner)
#
# Domain: darts.localhost – Caddy stellt dafür automatisch ein eigenes Test-Zertifikat aus.

set -uo pipefail

ZIP="${1:?ZIP fehlt}"
PHASE="${2:-install}"
BASE=/root/darts_dockertest
DOMAIN=darts.localhost
FEHLER=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
nok()  { printf '  \033[31m✗ %s\033[0m\n' "$1"; FEHLER=$((FEHLER + 1)); }
info() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
pruef() { # pruef "Beschreibung" befehl...
  local text="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$text"; else nok "$text"; fi
}
https() { curl -sS -k --max-time 10 --resolve "$DOMAIN:443:127.0.0.1" "$@"; }
header_von() { https -o /dev/null -D - "https://$DOMAIN$1" | tr -d '\r'; }
cid() { docker ps -q --filter "label=com.docker.compose.project=darts" --filter "label=com.docker.compose.service=$1"; }

entpacke() { # entpacke <zip> <ziel>
  rm -rf "$2"; mkdir -p "$2"
  unzip -q "$1" -d "$2" || { nok "unzip $1"; exit 1; }
  ls -d "$2"/darts_server_* | head -n1
}

pruefe_alles() {
  local erwartet_version="$1"
  info 'Container und Sicherheit'
  local d c
  d="$(cid darts)"; c="$(cid caddy)"
  [ -n "$d" ] && ok 'Container darts läuft' || { nok 'Container darts läuft nicht'; return; }
  [ -n "$c" ] && ok 'Container caddy läuft' || nok 'Container caddy läuft nicht'
  pruef 'Healthcheck: healthy' test "$(docker inspect -f '{{.State.Health.Status}}' "$d")" = healthy
  pruef 'Dateisystem nur lesbar' test "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$d")" = true
  pruef 'alle Linux-Rechte entzogen (cap_drop ALL)' sh -c "docker inspect -f '{{.HostConfig.CapDrop}}' $d | grep -q ALL"
  pruef 'no-new-privileges' sh -c "docker inspect -f '{{.HostConfig.SecurityOpt}}' $d | grep -q no-new-privileges"
  pruef 'Speichergrenze 256 MB' test "$(docker inspect -f '{{.HostConfig.Memory}}' "$d")" = 268435456
  pruef 'läuft als Benutzer darts (nicht root)' test "$(docker exec "$d" id -u)" = 10001
  pruef 'Port 8080 nur auf 127.0.0.1' sh -c "docker port $d 8080 | grep -qx '127.0.0.1:8080'"
  pruef 'Neustart-Regel unless-stopped' test "$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$d")" = unless-stopped
  pruef 'Server kann nichts ins Dateisystem schreiben' sh -c "! docker exec $d sh -c 'echo x > /app/x' 2>/dev/null"
  echo "  RAM: $(docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' | tr '\n' ' ')"

  info "HTTPS über Caddy (https://$DOMAIN)"
  pruef '/health → 200' sh -c "curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/health"
  local v
  v="$(https "https://$DOMAIN/version.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n1)"
  pruef "version.json meldet $erwartet_version (ist: ${v:-leer})" test "$v" = "$erwartet_version"
  local apk
  apk="$(https "https://$DOMAIN/version.json" | sed -n 's/.*"apk": *"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -n "$apk" ]; then
    local code typ
    code="$(https -o /tmp/darts_test.apk -w '%{http_code}' "https://$DOMAIN$apk")"
    pruef "APK-Download $apk → 200" test "$code" = 200
    pruef 'APK ist ein gültiges Android-Paket (ZIP mit AndroidManifest.xml)' sh -c 'unzip -l /tmp/darts_test.apk | grep -q AndroidManifest.xml'
    typ="$(header_von "$apk" | sed -n 's/^[Cc]ontent-[Tt]ype: *//p')"
    pruef "APK-Typ application/vnd.android.package-archive (ist: $typ)" sh -c "echo '$typ' | grep -q 'application/vnd.android.package-archive'"
  else
    nok 'version.json ohne apk-Eintrag'
  fi
  pruef 'Web-App: / liefert index.html mit Flutter' sh -c "curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/ | grep -q flutter_bootstrap"
  pruef 'Web-App: main.dart.js vorhanden' sh -c "curl -sfk -o /dev/null --max-time 20 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/main.dart.js"
  pruef 'Web-App: manifest.json' sh -c "curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/manifest.json | grep -q Darts"
  pruef 'Raum-Link /?room=ABC234 liefert die App' sh -c "curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 'https://$DOMAIN/?room=ABC234' | grep -q flutter_bootstrap"
  pruef 'sw.js wird nicht gecacht' sh -c "curl -sfk -D - -o /dev/null --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/sw.js | grep -qi 'cache-control:.*no-cache'"
  pruef 'HSTS-Header gesetzt' sh -c "curl -sfk -D - -o /dev/null --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/ | grep -qi strict-transport-security"
  pruef 'komprimiert ausgeliefert (gzip/zstd)' sh -c "curl -sfk -D - -o /dev/null -H 'Accept-Encoding: gzip' --max-time 20 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/main.dart.js | grep -qi 'content-encoding'"
  pruef 'HTTP leitet auf HTTPS um' sh -c "curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve $DOMAIN:80:127.0.0.1 http://$DOMAIN/ | grep -Eq '30[178]'"
  pruef 'unbekannte Datei → 404 bzw. App' sh -c "code=\$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/gibtsnicht.png); [ \"\$code\" = 404 ] || [ \"\$code\" = 200 ]"
  pruef 'kein Verzeichnis-Listing /apk/' sh -c "! curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/apk/ | grep -qi 'index of'"
  pruef 'keine .env über das Web abrufbar' sh -c "! curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/.env | grep -q DOMAIN="
  pruef 'Pfad-Trick ../ blockiert' sh -c "! curl -sfk --path-as-is --max-time 10 --resolve $DOMAIN:443:127.0.0.1 'https://$DOMAIN/../../etc/passwd' | grep -q root:"

  info 'WebSocket über Caddy'
  local antwort
  antwort="$(https -o /dev/null -w '%{http_code}' -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
      -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' --http1.1 --max-time 5 "https://$DOMAIN/ws" 2>/dev/null)"
  pruef "Upgrade auf /ws → 101 (ist: $antwort)" test "$antwort" = 101

  info 'Logs ohne Fehler'
  local logs
  logs="$(cd "$DIR" && docker compose --profile https logs --no-color darts 2>&1)"
  pruef 'Server-Log ohne ERROR/Exception' sh -c "! printf '%s' \"\$0\" | grep -Eiq 'error|exception|unhandled'" "$logs"
}

case "$PHASE" in
  install)
    info 'Vorbereitung: alte Testreste entfernen'
    (ls -d $BASE/*/darts_server_* 2>/dev/null | while read -r d; do (cd "$d" && docker compose --profile https down -v --remove-orphans >/dev/null 2>&1); done) || true
    rm -rf "$BASE"
    DIR="$(entpacke "$ZIP" "$BASE/v1")"
    echo "  entpackt nach $DIR"
    pruef 'install.sh ist im ZIP' test -f "$DIR/install.sh"
    pruef 'SCHNELLSTART.md ist im ZIP' test -f "$DIR/SCHNELLSTART.md"
    pruef 'keine .env im ZIP' test ! -f "$DIR/.env"
    pruef 'Server-Datei ist Linux-ELF x86-64' sh -c "file '$DIR/bin/darts_server' | grep -q 'ELF 64-bit.*x86-64'"
    pruef 'Textdateien mit LF (keine CRLF)' sh -c "! grep -l \$'\r' '$DIR/install.sh' '$DIR/docker-compose.yml' '$DIR/Caddyfile' '$DIR/.env.example' '$DIR/Dockerfile'"
    VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$DIR/version.json" | head -n1)"

    info 'Fehlerfall: install.sh ohne Domain und ohne Terminal'
    pruef 'bricht mit Hinweis ab' sh -c "cd '$DIR' && ! bash install.sh </dev/null >/tmp/inst0.log 2>&1 && grep -q 'Keine Domain' /tmp/inst0.log"
    rm -f "$DIR/.env"

    info "install.sh $DOMAIN (wie beim Freund)"
    if (cd "$DIR" && bash install.sh "$DOMAIN" </dev/null); then ok 'install.sh erfolgreich'; else nok 'install.sh fehlgeschlagen'; fi
    pruef '.env angelegt mit DOMAIN' grep -qx "DOMAIN=$DOMAIN" "$DIR/.env"
    pruef '.env mit PUBLIC_URL' grep -qx "PUBLIC_URL=https://$DOMAIN" "$DIR/.env"
    pruef '.env nur für Besitzer lesbar (600)' test "$(stat -c %a "$DIR/.env")" = 600
    pruefe_alles "$VERSION"

    info 'install.sh ein zweites Mal (darf nichts kaputt machen)'
    if (cd "$DIR" && bash install.sh </dev/null >/tmp/inst2.log 2>&1); then ok 'zweiter Lauf erfolgreich'; else nok 'zweiter Lauf fehlgeschlagen'; tail -n 30 /tmp/inst2.log; fi
    pruef 'install.sh status' sh -c "cd '$DIR' && bash install.sh status >/dev/null 2>&1"
    ;;

  restart)
    DIR="$(ls -d $BASE/v*/darts_server_* | tail -n1)"
    VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$DIR/version.json" | head -n1)"
    info 'Container neu starten'
    (cd "$DIR" && docker compose --profile https restart >/dev/null 2>&1)
    for i in $(seq 1 30); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$(cid darts)" 2>/dev/null)" = healthy ] && break; sleep 2; done
    pruefe_alles "$VERSION"
    info 'Docker-Dienst neu starten (wie Server-Neustart)'
    systemctl restart docker
    for i in $(seq 1 40); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$(cid darts)" 2>/dev/null)" = healthy ] && break; sleep 2; done
    pruef 'Container nach Docker-Neustart wieder da' test -n "$(cid darts)"
    pruef 'Caddy nach Docker-Neustart wieder da' test -n "$(cid caddy)"
    pruefe_alles "$VERSION"
    ;;

  update)
    OLD="$(ls -d $BASE/v1/darts_server_* | head -n1)"
    info 'Neue Version simulieren (gleiches ZIP, version.json auf Testversion gesetzt)'
    NEWBASE="$BASE/v2"
    rm -rf "$NEWBASE"; mkdir -p "$NEWBASE"
    unzip -q "$ZIP" -d "$NEWBASE"
    SRC="$(ls -d $NEWBASE/darts_server_* | head -n1)"
    DIR="$NEWBASE/darts_server_9.9.9"
    mv "$SRC" "$DIR"
    sed -i 's/"version": *"[^"]*"/"version": "9.9.9"/' "$DIR/version.json"
    if (cd "$DIR" && bash install.sh </dev/null >/tmp/inst_upd.log 2>&1); then ok 'Update mit install.sh erfolgreich'; else nok 'Update fehlgeschlagen'; tail -n 30 /tmp/inst_upd.log; fi
    pruef 'Einstellungen aus altem Ordner übernommen' grep -q 'Einstellungen übernommen' /tmp/inst_upd.log
    pruef '.env im neuen Ordner hat DOMAIN' grep -qx "DOMAIN=$DOMAIN" "$DIR/.env"
    pruef 'nur ein darts-Container (alter ersetzt)' test "$(docker ps -q --filter label=com.docker.compose.service=darts | wc -l)" = 1
    pruef 'Zertifikats-Volume blieb erhalten' sh -c "docker volume ls -q | grep -qx darts_caddy_data"
    pruefe_alles 9.9.9
    info 'Rollback: alten Ordner wieder starten'
    if (cd "$OLD" && bash install.sh </dev/null >/tmp/inst_rb.log 2>&1); then ok 'Rollback erfolgreich'; else nok 'Rollback fehlgeschlagen'; fi
    DIR="$OLD"
    VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$DIR/version.json" | head -n1)"
    pruefe_alles "$VERSION"
    ;;

  cleanup)
    info 'Aufräumen'
    for d in $BASE/v*/darts_server_*; do [ -d "$d" ] && (cd "$d" && docker compose --profile https down -v --remove-orphans >/dev/null 2>&1); done
    docker image rm -f darts-server:local >/dev/null 2>&1 || true
    rm -rf "$BASE" /tmp/darts_test.apk
    ok 'Testcontainer, Volumes, Image und Ordner entfernt'
    ;;

  *) echo "Unbekannte Phase: $PHASE"; exit 2 ;;
esac

echo
if [ "$FEHLER" -eq 0 ]; then printf '\033[32mPhase %s: alles OK\033[0m\n' "$PHASE"; else printf '\033[31mPhase %s: %d Fehler\033[0m\n' "$PHASE" "$FEHLER"; fi
exit "$FEHLER"
