#!/usr/bin/env bash
# Lokaler Test des ghcr.io-Wegs (läuft in WSL als root):
#   1. Image aus dem Quellcode bauen (docker/Dockerfile – genau wie GitHub Actions)
#   2. in eine lokale Registry (localhost:5000) pushen – spielt ghcr.io nach
#   3. darts-docker-Paket zusammenstellen (wie release.yml), install.sh darts.localhost
#   4. HTTPS, /app, APK, WebSocket, Sicherheit prüfen; E2E über Caddy
#   5. Update: neues Image (9.9.9) pushen -> bash install.sh update -> 9.9.9; autoupdate an/aus
#   6. aufräumen
#
#   bash ghcr_test.sh /mnt/c/dev/darts_counter
set -uo pipefail

REPO="${1:?Projektordner fehlt}"
BASE=/root/darts_ghcrtest
DOMAIN=darts.localhost
REG=localhost:5000
IMG="$REG/darts"
FEHLER=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
nok()  { printf '  \033[31m✗ %s\033[0m\n' "$1"; FEHLER=$((FEHLER + 1)); }
info() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
pruef() { local t="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$t"; else nok "$t"; fi; }
https() { curl -sS -k --max-time 10 --resolve "$DOMAIN:443:127.0.0.1" "$@"; }
cid() { docker ps -q --filter "label=com.docker.compose.project=darts" --filter "label=com.docker.compose.service=$1"; }
version_ist() { https "https://$DOMAIN/version.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n1; }

aufraeumen() {
  [ -d "$BASE/darts-docker" ] && (cd "$BASE/darts-docker" && docker compose down -v --remove-orphans >/dev/null 2>&1)
  (crontab -l 2>/dev/null | grep -v '# darts-autoupdate' || true) | crontab - 2>/dev/null || true
  docker rm -f darts-registry >/dev/null 2>&1 || true
  docker image rm -f "$IMG:latest" "$IMG:3.1.0" "$IMG:9.9.9" darts-update-test >/dev/null 2>&1 || true
  rm -rf "$BASE"
}

info 'Vorbereitung'
aufraeumen
mkdir -p "$BASE"
command -v crontab >/dev/null || (apt-get install -y -qq cron >/dev/null && systemctl enable --now cron >/dev/null 2>&1)
VERSION="$(python3 "$REPO/tool/ci/version_json.py" --print-version)"
APK="Darts_$VERSION.apk"
[ -f "$REPO/APK/$APK" ] || { nok "APK/$APK fehlt"; exit 1; }
# Build-Kontext wie in der CI: ci/apk + ci/version.json (im Projektordner, ist in .gitignore)
rm -rf "$REPO/ci"; mkdir -p "$REPO/ci/apk"
cp "$REPO/APK/$APK" "$REPO/ci/apk/"
python3 "$REPO/tool/ci/version_json.py" --apk "$APK" > "$REPO/ci/version.json"
ok "Version $VERSION, $APK"

info 'Image aus dem Quellcode bauen (docker/Dockerfile) – dauert beim ersten Mal länger'
if docker build -q -f "$REPO/docker/Dockerfile" --build-arg VERSION="$VERSION" -t "$IMG:latest" -t "$IMG:$VERSION" "$REPO" >/tmp/ghcr_build.log 2>&1; then
  ok 'Image gebaut'
else
  nok 'Image-Build fehlgeschlagen'; tail -n 40 /tmp/ghcr_build.log; exit 1
fi
echo "  Größe: $(docker image inspect -f '{{.Size}}' "$IMG:latest" | awk '{printf "%.0f MB", $1/1048576}')"
pruef 'keine Schlüssel im Image' sh -c "! docker run --rm --entrypoint sh $IMG:latest -c 'find / -xdev \\( -name key.properties -o -name \"*.jks\" -o -name \"*.keystore\" -o -name .env \\) 2>/dev/null' | grep -q ."
pruef 'Web-App im Image' sh -c "docker run --rm --entrypoint sh $IMG:latest -c 'test -f /app/web/index.html && test -f /app/web/main.dart.js'"
pruef "APK im Image ($APK)" sh -c "docker run --rm --entrypoint sh $IMG:latest -c 'test -s /app/apk/$APK'"

info 'Lokale Registry (spielt ghcr.io) + Push'
docker run -d --name darts-registry -p 127.0.0.1:5000:5000 registry:2 >/dev/null
for i in $(seq 1 20); do curl -fs http://$REG/v2/ >/dev/null && break; sleep 1; done
pruef 'Push latest' docker push -q "$IMG:latest"
pruef "Push $VERSION" docker push -q "$IMG:$VERSION"
# lokale Kopie löschen, damit install.sh wirklich aus der Registry lädt
docker image rm -f "$IMG:latest" "$IMG:$VERSION" >/dev/null 2>&1

info 'Paket darts-docker zusammenstellen (wie release.yml)'
D="$BASE/darts-docker"; mkdir -p "$D"
for f in deploy/ghcr/docker-compose.yml deploy/ghcr/ANLEITUNG.md deploy/Caddyfile deploy/install.sh; do tr -d '\r' < "$REPO/$f" > "$D/$(basename "$f")"; done
{ echo "# Fertiges Image von ghcr.io (latest = immer die neueste Version)"; echo "DARTS_IMAGE=$IMG:latest"; echo; tr -d '\r' < "$REPO/deploy/.env.example"; } > "$D/.env.example"
pruef 'kein bin/darts_server im Paket (ghcr.io-Weg)' test ! -e "$D/bin/darts_server"

info "install.sh $DOMAIN (Image wird aus der Registry geladen)"
if (cd "$D" && bash install.sh "$DOMAIN" </dev/null >/tmp/ghcr_inst.log 2>&1); then ok 'install.sh erfolgreich'; else nok 'install.sh fehlgeschlagen'; tail -n 30 /tmp/ghcr_inst.log; fi
pruef 'Image-Weg erkannt (laden statt bauen)' grep -q 'Darts laden und starten' /tmp/ghcr_inst.log
pruef 'Image aus .env genommen' grep -q "Image: $IMG:latest" /tmp/ghcr_inst.log

info 'Prüfungen'
d="$(cid darts)"
pruef 'Container darts läuft' test -n "$d"
pruef 'Container caddy läuft' test -n "$(cid caddy)"
pruef 'Healthcheck: healthy' test "$(docker inspect -f '{{.State.Health.Status}}' "$d")" = healthy
pruef 'Dateisystem nur lesbar' test "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$d")" = true
pruef 'cap_drop ALL' sh -c "docker inspect -f '{{.HostConfig.CapDrop}}' $d | grep -q ALL"
pruef 'läuft als Benutzer darts (10001)' test "$(docker exec "$d" id -u)" = 10001
pruef 'Port 8080 nicht nach außen veröffentlicht' test -z "$(docker port "$d" 2>/dev/null)"
pruef "version.json meldet $VERSION" test "$(version_ist)" = "$VERSION"
pruef '/health über HTTPS' sh -c "curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/health"
pruef 'Web-App über HTTPS' sh -c "curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/ | grep -q flutter_bootstrap"
pruef '/app mit Verbinden-Link' sh -c "curl -sfk --max-time 10 --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN/app | grep -q 'intent://connect?server=https%3A%2F%2F$DOMAIN'"
code="$(https -o /tmp/ghcr.apk -w '%{http_code}' "https://$DOMAIN/apk/$APK")"
pruef "APK-Download → 200 (ist $code)" test "$code" = 200
pruef 'APK identisch mit der lokalen' cmp -s /tmp/ghcr.apk "$REPO/APK/$APK"
ws="$(https -o /dev/null -w '%{http_code}' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' --http1.1 --max-time 5 "https://$DOMAIN/ws" 2>/dev/null)"
pruef "WebSocket /ws → 101 (ist $ws)" test "$ws" = 101

info 'E2E-Protokolltest über Caddy'
if docker run --rm --network host --add-host darts.localhost:127.0.0.1 \
    -e DARTS_E2E_URL=https://darts.localhost -e DARTS_E2E_INSECURE=1 \
    -v "$REPO/tool/e2e:/src/tool/e2e:ro" -v "$REPO/packages:/src/packages:ro" dart:stable \
    sh -c 'mkdir -p /w/tool && cp -r /src/packages /w/ && cp -r /src/tool/e2e /w/tool/ && rm -rf /w/tool/e2e/.dart_tool /w/tool/e2e/pubspec.lock && cd /w/tool/e2e && dart pub get >/dev/null && dart test' >/tmp/ghcr_e2e.log 2>&1; then
  ok 'E2E grün'
else
  nok 'E2E fehlgeschlagen'; tail -n 20 /tmp/ghcr_e2e.log
fi

info 'Update: neue Version 9.9.9 in die Registry, dann bash install.sh update'
U="$BASE/update"; mkdir -p "$U"
sed 's/"version": *"[^"]*"/"version": "9.9.9"/' "$REPO/ci/version.json" > "$U/version.json"
printf 'FROM %s:%s\nCOPY version.json /app/version.json\n' "$IMG" "$VERSION" > "$U/Dockerfile"
docker pull -q "$IMG:$VERSION" >/dev/null
docker build -q -t "$IMG:latest" -t "$IMG:9.9.9" "$U" >/dev/null && docker push -q "$IMG:latest" >/dev/null && docker push -q "$IMG:9.9.9" >/dev/null
if (cd "$D" && bash install.sh update </dev/null >/tmp/ghcr_upd.log 2>&1); then ok 'install.sh update erfolgreich'; else nok 'update fehlgeschlagen'; tail -n 20 /tmp/ghcr_upd.log; fi
pruef 'meldet „Aktualisiert“' grep -q 'Aktualisiert' /tmp/ghcr_upd.log
pruef 'version.json meldet jetzt 9.9.9' test "$(version_ist)" = 9.9.9
if (cd "$D" && bash install.sh update </dev/null >/tmp/ghcr_upd2.log 2>&1); then ok 'zweites update ok'; else nok 'zweites update fehlgeschlagen'; fi
pruef 'meldet „Schon die neueste Version“' grep -q 'Schon die neueste' /tmp/ghcr_upd2.log
pruef 'Zertifikats-Volume blieb' sh -c "docker volume ls -q | grep -qx darts_caddy_data"

info 'Automatische Updates'
(cd "$D" && bash install.sh autoupdate an >/dev/null 2>&1)
pruef 'autoupdate an → crontab-Eintrag' sh -c "crontab -l | grep -q 'install.sh update.*# darts-autoupdate'"
(cd "$D" && bash install.sh autoupdate an >/dev/null 2>&1)
pruef 'zweimal an → nur ein Eintrag' test "$(crontab -l | grep -c '# darts-autoupdate')" = 1
(cd "$D" && bash install.sh autoupdate aus >/dev/null 2>&1)
pruef 'autoupdate aus → Eintrag weg' sh -c "! crontab -l 2>/dev/null | grep -q '# darts-autoupdate'"

info 'Fehlerfall: Image nicht erreichbar'
sed -i "s#^DARTS_IMAGE=.*#DARTS_IMAGE=$REG/gibtsnicht:latest#" "$D/.env"
pruef 'update bricht mit Login-Hinweis ab' sh -c "cd '$D' && ! bash install.sh update </dev/null >/tmp/ghcr_err.log 2>&1 && grep -q 'docker login ghcr.io' /tmp/ghcr_err.log"

info 'Aufräumen'
aufraeumen
rm -rf "$REPO/ci"
ok 'Container, Registry, Images und Testordner entfernt'

echo
if [ "$FEHLER" -eq 0 ]; then printf '\033[32mGHCR-TEST: ALLES OK\033[0m\n'; else printf '\033[31mGHCR-TEST: %d Fehler\033[0m\n' "$FEHLER"; fi
exit "$FEHLER"
