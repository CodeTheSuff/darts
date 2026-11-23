# Darts – Docker-Image aus dem Quellcode (für GitHub Actions → ghcr.io).
#
# Baut Web-App (Flutter) und Server (Dart) selbst. Die APK wird NICHT gebaut (braucht den geheimen
# Release-Schlüssel), sondern liegt fertig im Build-Kontext unter ci/apk/ – die CI lädt sie aus dem
# GitHub-Release. version.json erzeugt die CI unter ci/version.json (tool/ci/version_json.py).
#
# Lokal (Projektwurzel):
#   mkdir -p ci/apk && cp APK/Darts_<v>.apk ci/apk/ && python tool/ci/version_json.py --apk Darts_<v>.apk > ci/version.json
#   docker build -f docker/Dockerfile -t darts:test .
#
# Laufzeit, Benutzer, Healthcheck und Umgebungsvariablen sind identisch mit deploy/Dockerfile (ZIP-Weg).

ARG FLUTTER_VERSION=3.50.0
ARG DART_VERSION=3.14.0

# ---------------------------------------------------------------- Web-App
FROM debian:stable-slim AS web
ARG FLUTTER_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# Offizielles Flutter in genau der Version, mit der auch lokal gebaut wird
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /flutter
ENV PATH=/flutter/bin:$PATH
RUN flutter config --no-analytics --enable-web >/dev/null && flutter precache --web
WORKDIR /src
# Erst nur die Abhängigkeiten (besser cachebar)
COPY pubspec.yaml pubspec.lock ./
COPY packages/ packages/
RUN flutter pub get
COPY . .
RUN flutter build web --release --base-href=/

# ---------------------------------------------------------------- Server
FROM dart:${DART_VERSION} AS server
WORKDIR /src
COPY packages/darts_protocol/ packages/darts_protocol/
COPY server/ server/
WORKDIR /src/server
RUN mkdir -p /out && dart pub get && dart compile exe bin/server.dart -o /out/darts_server

# ---------------------------------------------------------------- Laufzeit
FROM debian:stable-slim

RUN groupadd --system --gid 10001 darts \
 && useradd --system --uid 10001 --gid darts --no-create-home --shell /usr/sbin/nologin darts

WORKDIR /app
COPY --from=server /out/darts_server /app/bin/darts_server
COPY --from=web /src/build/web/ /app/web/
COPY ci/apk/ /app/apk/
COPY ci/version.json /app/version.json
RUN chmod 0755 /app/bin/darts_server && chmod -R a+rX /app

ARG VERSION=dev
LABEL org.opencontainers.image.title="Darts" \
      org.opencontainers.image.description="Darts – Vermittlungs-Server, Web-App und Android-App" \
      org.opencontainers.image.version="${VERSION}"

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

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${PORT:-8080} && printf 'GET /health HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && head -n 1 <&3 | grep -q ' 200'"]

ENTRYPOINT ["/app/bin/darts_server"]
