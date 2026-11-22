<#
.SYNOPSIS
  Testet das Release-ZIP lokal in Docker (WSL/Ubuntu) – genau so, wie der Freund es installiert.

.DESCRIPTION
  1. Prüft WSL/Ubuntu, richtet beim ersten Mal Docker Engine + compose darin ein (als root, ohne Passwort)
  2. Phase install:  ZIP entpacken, install.sh darts.localhost, Sicherheit/HTTPS/Web/APK/WebSocket prüfen
  3. E2E-Protokolltest (Host + 2 Gäste, X01 bis zum Sieg …) gegen https://darts.localhost – über Caddy
  4. Phase restart:  Container- und Docker-Neustart
  5. Phase update:   neue Version daneben entpacken, install.sh übernimmt .env, Rollback
  6. Phase cleanup:  alles wieder weg (mit -Keep bleibt der Server für Browser-/Handy-Tests laufen)

  Aufruf in der Projektwurzel:
    powershell -ExecutionPolicy Bypass -File tool\docker\docker_test.ps1
    powershell -ExecutionPolicy Bypass -File tool\docker\docker_test.ps1 -Zip release\darts_server_3.0.0.zip -Keep
#>
[CmdletBinding()]
param(
    [string]$Zip = '',
    [string]$Distro = 'Ubuntu',
    [switch]$Keep,
    [switch]$SkipE2e
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fehler = 0

function Write-Step([string]$text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }

function Invoke-Wsl([string]$cmd) {
    # Als root: kein Passwort nötig, Docker ohne sudo.
    & wsl.exe -d $Distro -u root -- bash -lc $cmd | Out-Host
    return $LASTEXITCODE
}

function ConvertTo-WslPath([string]$p) {
    $full = (Resolve-Path $p).Path
    $drive = $full.Substring(0, 1).ToLower()
    return '/mnt/' + $drive + ($full.Substring(2) -replace '\\', '/')
}

# ------------------------------------------------------------------ WSL
Write-Step "WSL / $Distro prüfen"
$list = (& wsl.exe -l -q 2>$null) -join "`n" -replace "`0", ''
if ($list -notmatch "(?m)^$Distro") {
    throw "WSL-Distribution '$Distro' fehlt. Einmalig in PowerShell (Administrator): wsl --install -d $Distro – danach Neustart und Ubuntu einmal öffnen (Benutzer anlegen)."
}
Write-Host "$Distro vorhanden"

Write-Step 'Docker in WSL prüfen bzw. einrichten'
$hasDocker = Invoke-Wsl 'command -v docker >/dev/null && docker compose version >/dev/null 2>&1'
if ($hasDocker -ne 0) {
    Write-Host 'Docker fehlt – installiere docker.io + docker-compose-v2 aus den Ubuntu-Paketquellen …'
    $rc = Invoke-Wsl 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq docker.io docker-compose-v2 unzip curl file >/dev/null && systemctl enable --now docker'
    if ($rc -ne 0) { throw 'Docker-Installation in WSL fehlgeschlagen.' }
}
$null = Invoke-Wsl 'command -v unzip >/dev/null && command -v file >/dev/null || (apt-get install -y -qq unzip file curl >/dev/null)'
$rc = Invoke-Wsl 'systemctl is-active --quiet docker || systemctl start docker; docker info >/dev/null 2>&1'
if ($rc -ne 0) { throw 'Docker läuft in WSL nicht (systemd aktiv? /etc/wsl.conf: [boot] systemd=true).' }
$null = Invoke-Wsl 'docker --version; docker compose version'

# ------------------------------------------------------------------ ZIP
if ($Zip -eq '') {
    $m = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+' | Select-Object -First 1
    $Zip = Join-Path $root "release\darts_server_$($m.Matches[0].Groups[1].Value).zip"
}
if (-not (Test-Path $Zip)) { throw "ZIP fehlt: $Zip (vorher tool\build_release.ps1 laufen lassen)." }
Write-Host "ZIP: $Zip"
$zipWsl = ConvertTo-WslPath $Zip
$testWsl = ConvertTo-WslPath (Join-Path $PSScriptRoot 'docker_test.sh')
# Skript mit LF nach /tmp kopieren (Windows-Checkout kann CRLF haben)
$null = Invoke-Wsl "tr -d '\r' < '$testWsl' > /tmp/darts_docker_test.sh"

function Invoke-Phase([string]$phase) {
    Write-Step "Phase $phase"
    $rc = Invoke-Wsl "bash /tmp/darts_docker_test.sh '$zipWsl' $phase"
    if ($rc -ne 0) { $script:fehler += $rc; Write-Host "Phase $phase meldet $rc Fehler" -ForegroundColor Red }
}

Invoke-Phase 'install'

# ------------------------------------------------------------------ E2E über Caddy
if (-not $SkipE2e) {
    Write-Step 'E2E-Protokolltest gegen https://darts.localhost (Dart im Docker-Container)'
    $repoWsl = ConvertTo-WslPath $root
    $cmd = @(
        "docker run --rm --network host --add-host darts.localhost:127.0.0.1",
        "-e DARTS_E2E_URL=https://darts.localhost -e DARTS_E2E_INSECURE=1",
        "-v '${repoWsl}/tool/e2e:/src/tool/e2e:ro' -v '${repoWsl}/packages:/src/packages:ro' dart:stable",
        "sh -c 'mkdir -p /w/tool && cp -r /src/packages /w/ && cp -r /src/tool/e2e /w/tool/ && rm -rf /w/tool/e2e/.dart_tool /w/tool/e2e/pubspec.lock && cd /w/tool/e2e && dart pub get >/dev/null && dart test -r expanded'"
    ) -join ' '
    $rc = Invoke-Wsl $cmd
    if ($rc -ne 0) { $fehler += 1; Write-Host 'E2E-Test fehlgeschlagen' -ForegroundColor Red } else { Write-Host 'E2E-Test grün' -ForegroundColor Green }
}

Invoke-Phase 'restart'
Invoke-Phase 'update'

if ($Keep) {
    Write-Step 'Server bleibt laufen (-Keep)'
    Write-Host 'Im Browser: https://darts.localhost (Testzertifikat – Warnung bestätigen). Aufräumen später mit:'
    Write-Host "  wsl -d $Distro -u root -- bash /tmp/darts_docker_test.sh '$zipWsl' cleanup"
} else {
    Invoke-Phase 'cleanup'
}

Write-Host ''
if ($fehler -eq 0) {
    Write-Host 'DOCKER-TEST: ALLES OK' -ForegroundColor Green
} else {
    Write-Host "DOCKER-TEST: $fehler Fehler" -ForegroundColor Red
    exit 1
}
