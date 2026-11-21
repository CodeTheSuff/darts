<#
.SYNOPSIS
  Baut das Hosting-Paket release\darts_server_<version>.zip für den Freund.

.DESCRIPTION
  1. Version/Build aus pubspec.yaml (z. B. "version: 3.0.0+19")
  2. flutter build web --release                          -> web/
  3. Server für Linux x64 cross-kompilieren (dart compile exe) -> bin/darts_server
  4. APK aus APK\Darts_<version>.apk übernehmen (wird hier NICHT gebaut – braucht den geheimen Schlüssel)
  5. version.json erzeugen (Änderungsliste aus lib/ui/about_screen.dart oder -Notes)
  6. deploy/-Dateien + ANLEITUNG_HOSTING.md dazu (Zeilenenden LF)
  7. ZIP bauen, Sicherheitsprüfung (keine Schlüssel/Passwörter), Inhaltsübersicht

  PowerShell-5.1-kompatibel. Aufruf in der Projektwurzel:
    powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
  Testlauf ohne Server-Code / ohne APK:
    powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -SkipServer -SkipApk

.PARAMETER SkipWeb
  Web nicht neu bauen, vorhandenes build\web nehmen (fehlt es, kommt ein Platzhalter rein -> Test-ZIP).
.PARAMETER SkipServer
  Server nicht kompilieren (Platzhalter statt Binärdatei -> Test-ZIP mit Endung _test).
.PARAMETER SkipApk
  Keine APK beilegen (apk/ bleibt leer, version.json ohne "apk").
.PARAMETER ApkPath
  Andere APK-Datei statt APK\Darts_<version>.apk.
.PARAMETER Notes
  Änderungsliste für version.json (statt aus about_screen.dart gelesen).
.PARAMETER BaseHref
  base href für den Web-Build (Standard "/"; z. B. "/darts/" bei Unterpfad).
#>
[CmdletBinding()]
param(
    [switch]$SkipWeb,
    [switch]$SkipServer,
    [switch]$SkipApk,
    [string]$ApkPath = '',
    [string[]]$Notes = @(),
    [string]$BaseHref = '/'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$root = Split-Path -Parent $PSScriptRoot
$flutter = 'C:\dev\flutter\bin\flutter.bat'
$dart = 'C:\dev\flutter\bin\dart.bat'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$isTest = $false

function Write-Step([string]$text) {
    Write-Host ''
    Write-Host "==> $text" -ForegroundColor Cyan
}

function Invoke-Tool([string]$exe, [string[]]$arguments, [string]$workDir) {
    Push-Location $workDir
    try {
        & $exe @arguments
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0) { throw "Befehl fehlgeschlagen (Exit $code): $exe $($arguments -join ' ')" }
}

# Textdatei mit LF-Zeilenenden und UTF-8 ohne BOM kopieren (Linux-Server, systemd, docker compose).
function Copy-TextLf([string]$src, [string]$dst) {
    $text = [System.IO.File]::ReadAllText($src)
    $text = $text -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($dst, $text, $utf8)
}

function Format-Size([long]$bytes) {
    if ($bytes -ge 1MB) { return ('{0:N1} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N0} KB' -f ($bytes / 1KB)) }
    return "$bytes B"
}

# ---------------------------------------------------------------- Version
Write-Step 'Version aus pubspec.yaml'
$m = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' | Select-Object -First 1
if ($null -eq $m) { throw 'Keine Zeile "version: x.y.z+n" in pubspec.yaml gefunden.' }
$version = $m.Matches[0].Groups[1].Value
$build = [int]$m.Matches[0].Groups[2].Value
Write-Host "Version $version, Build $build"

# Protokollversion aus dem gemeinsamen Paket (relayProtocol)
$minProtocol = 3
$framesFile = Join-Path $root 'packages\darts_protocol\lib\src\frames.dart'
if (Test-Path $framesFile) {
    $pm = Select-String -Path $framesFile -Pattern 'const relayProtocol = (\d+);' | Select-Object -First 1
    if ($null -ne $pm) { $minProtocol = [int]$pm.Matches[0].Groups[1].Value }
}
Write-Host "minProtocol $minProtocol"

$releaseDir = Join-Path $root 'release'
$name = "darts_server_$version"
$stage = Join-Path $releaseDir $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
# Alte ZIPs dieser Version gleich weg, damit nach einem Fehler kein veraltetes Paket herumliegt.
foreach ($old in @("$name.zip", "${name}_test.zip")) {
    $oldPath = Join-Path $releaseDir $old
    if (Test-Path $oldPath) { Remove-Item -Force $oldPath }
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($sub in @('bin', 'web', 'apk')) { New-Item -ItemType Directory -Force -Path (Join-Path $stage $sub) | Out-Null }

# ---------------------------------------------------------------- Web
$webBuild = Join-Path $root 'build\web'
if ($SkipWeb) {
    Write-Step 'Web-Build übersprungen (-SkipWeb)'
} else {
    Write-Step 'flutter build web --release'
    Invoke-Tool $flutter @('build', 'web', '--release', "--base-href=$BaseHref") $root
}
if (Test-Path (Join-Path $webBuild 'index.html')) {
    Copy-Item -Path (Join-Path $webBuild '*') -Destination (Join-Path $stage 'web') -Recurse -Force
    Write-Host "Web-Build übernommen aus $webBuild"
} else {
    if (-not $SkipWeb) { throw "Web-Build fehlt: $webBuild\index.html" }
    Write-Warning 'Kein build\web vorhanden – Platzhalter-Seite (Test-ZIP).'
    [System.IO.File]::WriteAllText((Join-Path $stage 'web\index.html'), "<!doctype html><title>Darts</title><p>Testpaket ohne Web-Build</p>`n", $utf8)
    $isTest = $true
}

# ---------------------------------------------------------------- Server
$serverDir = Join-Path $root 'server'
$serverBin = Join-Path $stage 'bin\darts_server'
if ($SkipServer) {
    Write-Step 'Server übersprungen (-SkipServer) – Platzhalter, Test-ZIP'
    [System.IO.File]::WriteAllText($serverBin, "#!/bin/sh`necho 'Testpaket ohne Server-Binaerdatei' >&2`nexit 1`n", $utf8)
    $isTest = $true
} else {
    Write-Step 'Server für Linux x64 kompilieren'
    if (-not (Test-Path (Join-Path $serverDir 'bin\server.dart'))) {
        throw 'server\bin\server.dart fehlt (Server noch nicht da? Dann -SkipServer zum Testen).'
    }
    Invoke-Tool $dart @('pub', 'get') $serverDir
    # Cross-Kompilierung geht ab Dart 3.8 auch unter Windows. Ersatzweg: deploy\Dockerfile.build
    Invoke-Tool $dart @('compile', 'exe', 'bin\server.dart', '--target-os=linux', '--target-arch=x64', '-o', $serverBin) $serverDir
    $head = New-Object byte[] 4
    $fs = [System.IO.File]::OpenRead($serverBin)
    try { [void]$fs.Read($head, 0, 4) } finally { $fs.Close() }
    if (-not ($head[0] -eq 0x7F -and $head[1] -eq 0x45 -and $head[2] -eq 0x4C -and $head[3] -eq 0x46)) {
        throw 'bin\darts_server ist keine Linux-ELF-Datei.'
    }
    Write-Host "Linux-Binärdatei: $(Format-Size (Get-Item $serverBin).Length)"
}

# ---------------------------------------------------------------- APK
$apkName = "Darts_$version.apk"
$apkUrl = $null
if ($SkipApk) {
    Write-Step 'APK übersprungen (-SkipApk)'
} else {
    Write-Step 'APK übernehmen'
    if ($ApkPath -eq '') { $ApkPath = Join-Path $root "APK\$apkName" }
    if (-not (Test-Path $ApkPath)) {
        throw "APK fehlt: $ApkPath (Release-APK vorher separat bauen und dort ablegen, oder -SkipApk)."
    }
    Copy-Item -Path $ApkPath -Destination (Join-Path $stage "apk\$apkName")
    $apkUrl = "/apk/$apkName"
    Write-Host "APK: $ApkPath ($(Format-Size (Get-Item $ApkPath).Length))"
}

# ---------------------------------------------------------------- version.json
Write-Step 'version.json'
$noteList = @()
if ($Notes.Count -gt 0) {
    $noteList = @($Notes)
} else {
    $about = Join-Path $root 'lib\ui\about_screen.dart'
    if (Test-Path $about) {
        $src = [System.IO.File]::ReadAllText($about)
        $start = $src.IndexOf("'$version': [")
        if ($start -ge 0) {
            $end = $src.IndexOf('],', $start)
            if ($end -lt 0) { $end = $src.Length }
            $block = $src.Substring($start, $end - $start)
            $rx = [regex]"\(\s*Icons\.\w+\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*,?\s*\)"
            foreach ($e in $rx.Matches($block)) {
                $title = $e.Groups[1].Value -replace "\\'", "'"
                $desc = $e.Groups[2].Value -replace "\\'", "'"
                $noteList += "${title}: $desc"
            }
        }
    }
    if ($noteList.Count -eq 0) { Write-Warning "Keine Änderungsliste für $version gefunden (-Notes angeben?)." }
}
$info = [ordered]@{
    version     = $version
    build       = $build
    minProtocol = $minProtocol
}
if ($null -ne $apkUrl) { $info['apk'] = $apkUrl }
$info['notes'] = [object[]]$noteList
$json = ConvertTo-Json -InputObject $info -Depth 4
[System.IO.File]::WriteAllText((Join-Path $stage 'version.json'), ($json -replace "`r`n", "`n") + "`n", $utf8)
Write-Host $json

# ---------------------------------------------------------------- deploy + Anleitung
Write-Step 'deploy-Dateien und Anleitung'
$deployFiles = @('Dockerfile', 'docker-compose.yml', 'Caddyfile', 'nginx-darts.conf', 'darts.service', '.env.example', '.dockerignore')
foreach ($f in $deployFiles) {
    $src = Join-Path $root "deploy\$f"
    if (-not (Test-Path $src)) { throw "deploy\$f fehlt." }
    Copy-TextLf $src (Join-Path $stage $f)
}
$guide = Join-Path $root 'ANLEITUNG_HOSTING.md'
if (-not (Test-Path $guide)) { throw 'ANLEITUNG_HOSTING.md fehlt.' }
Copy-TextLf $guide (Join-Path $stage 'ANLEITUNG_HOSTING.md')

# ---------------------------------------------------------------- Sicherheitsprüfung (Ordner)
Write-Step 'Sicherheitsprüfung'
$badNames = @('key.properties', 'local.properties', '.env', '*.jks', '*.keystore', '*.p12', '*.pfx', '*.pem', '*.key')
$badText = @('storePassword', 'keyPassword', 'storeFile=', 'BEGIN PRIVATE KEY', 'BEGIN RSA PRIVATE KEY', 'BEGIN EC PRIVATE KEY')
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$problems = @()
$allFiles = @(Get-ChildItem -Path $stage -Recurse -Force -File)
foreach ($file in $allFiles) {
    foreach ($pattern in $badNames) {
        if ($file.Name -like $pattern) { $problems += "verbotene Datei: $($file.FullName)" }
    }
    $content = $latin1.GetString([System.IO.File]::ReadAllBytes($file.FullName))
    foreach ($t in $badText) {
        if ($content.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $problems += "verdächtiger Inhalt '$t' in $($file.FullName)"
        }
    }
    $content = $null
}
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw 'Sicherheitsprüfung fehlgeschlagen – kein ZIP gebaut.'
}
Write-Host "OK: $($allFiles.Count) Dateien geprüft, keine Schlüssel/Passwörter."

# ---------------------------------------------------------------- ZIP
$zipName = $name
if ($isTest) { $zipName = "${name}_test" }
$zip = Join-Path $releaseDir "$zipName.zip"
Write-Step "ZIP: $zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $allFiles) {
        $rel = $file.FullName.Substring($stage.Length + 1) -replace '\\', '/'
        $entry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, "$name/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
        # Unix-Rechte mitgeben (wird nicht von jedem unzip ausgewertet – Anleitung sagt chmod +x)
        try {
            if ($rel -eq 'bin/darts_server') { $entry.ExternalAttributes = (0x81ED -shl 16) } else { $entry.ExternalAttributes = (0x81A4 -shl 16) }
        } catch { }
    }
} finally {
    $archive.Dispose()
}

# Sicherheitsprüfung (ZIP-Einträge)
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    foreach ($e in $check.Entries) {
        foreach ($pattern in $badNames) {
            if ($e.Name -like $pattern) { $problems += "verbotene Datei im ZIP: $($e.FullName)" }
        }
        if ($e.FullName.Contains('\')) { $problems += "Backslash im ZIP-Pfad: $($e.FullName)" }
    }
    $entryCount = $check.Entries.Count
} finally {
    $check.Dispose()
}
if ($problems.Count -gt 0) {
    Remove-Item -Force $zip
    $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw 'Sicherheitsprüfung des ZIP fehlgeschlagen – ZIP gelöscht.'
}

# ---------------------------------------------------------------- Übersicht
Write-Step 'Inhalt'
foreach ($item in (Get-ChildItem -Path $stage -Force | Sort-Object Name)) {
    if ($item.PSIsContainer) {
        $files = @(Get-ChildItem -Path $item.FullName -Recurse -Force -File)
        $size = 0
        foreach ($f in $files) { $size += $f.Length }
        Write-Host ('  {0,-24} {1,10}  ({2} Dateien)' -f "$($item.Name)/", (Format-Size $size), $files.Count)
    } else {
        Write-Host ('  {0,-24} {1,10}' -f $item.Name, (Format-Size $item.Length))
    }
}
Write-Host ''
Write-Host "ZIP: $zip" -ForegroundColor Green
Write-Host "     $(Format-Size (Get-Item $zip).Length), $entryCount Einträge"
if ($isTest) {
    Write-Warning 'TESTPAKET (Platzhalter für Server oder Web) – nicht an den Freund schicken!'
}
if ($SkipApk) {
    Write-Warning 'Ohne APK: Selbst-Update der Android-App ist mit diesem Paket nicht möglich.'
}
