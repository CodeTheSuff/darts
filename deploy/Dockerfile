# Darts – Laufzeit-Image für den Vermittlungs-Server + Web-App.
#
# Dieses Dockerfile liegt im entpackten Release-Ordner (darts_server_<version>/) und nutzt die
# FERTIGEN Dateien daraus. Auf dem Server wird nichts kompiliert, Flutter/Dart sind nicht nötig.
#
#   bin/darts_server   Linux-x64-Binärdatei (dart compile exe)
#   web/               Flutter-Web-Build
#   apk/               aktuelle Android-APK (Selbst-Update)
#   version.json       Version + Änderungsliste
#
# Bauen/Starten:  docker compose up -d --build   (siehe ANLEITUNG_HOSTING.md)

FROM debian:stable-slim

# Eigener Benutzer ohne Login und ohne Home-Verzeichnis.
RUN groupadd --system --gid 10001 darts \
 && useradd --system --uid 10001 --gid darts --no-create-home --shell /usr/sbin/nologin darts

WORKDIR /app

COPY bin/darts_server /app/bin/darts_server
COPY web/ /app/web/
COPY apk/ /app/apk/
COPY version.json /app/version.json

# Ausführbar machen (beim Entpacken eines ZIP geht das Recht verloren); alles gehört root,
# der Dienst darf nur lesen.
RUN chmod 0755 /app/bin/darts_server \
 && chmod -R a+rX /app

ENV PORT=8080 \
    HOST=0.0.0.0 \
    WEB_DIR=/app/web \
    APK_DIR=/app/apk \
    VERSION_FILE=/app/version.json \
    ROOM_TTL_HOURS=24 \
    MAX_ROOMS=500 \
    MAX_PEERS_PER_ROOM=8 \
    MIN_PROTOCOL=3 \
    TRUST_PROXY=false \
    LOG_LEVEL=info

USER darts:darts
EXPOSE 8080

# Lebenszeichen ohne zusätzliche Pakete (curl ist im slim-Image nicht drin): bash + /dev/tcp.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${PORT:-8080} && printf 'GET /health HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && head -n 1 <&3 | grep -q ' 200'"]

ENTRYPOINT ["/app/bin/darts_server"]
