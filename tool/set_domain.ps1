<#
.SYNOPSIS
  Trägt die Domain des Darts-Servers EINMAL ein – alle anderen Skripte übernehmen sie automatisch.

.DESCRIPTION
  Schreibt die Domain nach deploy\domain.txt. Von dort liest sie:
    - tool\build_release.ps1  -> baut die APK mit fest eingebauter Server-Adresse und trägt die
                                 Domain in .env.example im ZIP ein (install.sh fragt dann nicht mehr)
    - die App selbst           -> über --dart-define=DARTS_SERVER_URL beim Bauen
    - die Web-App              -> braucht nichts, sie nimmt immer den Server, von dem sie geladen wird

  Aufruf (oder einfach Domain_eintragen.cmd doppelklicken):
    powershell -ExecutionPolicy Bypass -File tool\set_domain.ps1                       (fragt nach)
    powershell -ExecutionPolicy Bypass -File tool\set_domain.ps1 -Domain darts.xy.de
    powershell -ExecutionPolicy Bypass -File tool\set_domain.ps1 -Domain darts.xy.de -Build
    powershell -ExecutionPolicy Bypass -File tool\set_domain.ps1 -Show
    powershell -ExecutionPolicy Bypass -File tool\set_domain.ps1 -Clear              (zurück auf "ohne Domain")

.PARAMETER Build
  Danach gleich APK + ZIP bauen (tool\build_release.ps1).
#>
[CmdletBinding()]
param(
    [string]$Domain = '',
    [switch]$Build,
    [switch]$Show,
    [switch]$Clear
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$file = Join-Path $root 'deploy\domain.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-CurrentDomain {
    if (-not (Test-Path $file)) { return '' }
    foreach ($line in [System.IO.File]::ReadAllLines($file)) {
        $t = $line.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#')) { return $t }
    }
    return ''
}

$current = Get-CurrentDomain
if ($Show) {
    if ($current -eq '') { Write-Host 'Noch keine Domain eingetragen.' } else { Write-Host "Eingetragene Domain: $current" }
    exit 0
}

if ($Clear) {
    if (Test-Path $file) { Remove-Item -Force $file }
    Write-Host 'Domain entfernt – Builds sind wieder ohne eingebaute Server-Adresse.' -ForegroundColor Yellow
    exit 0
}

if ($Domain -eq '') {
    if ($current -ne '') { Write-Host "Aktuell eingetragen: $current" }
    $Domain = Read-Host 'Domain des Darts-Servers (z. B. darts.beispiel.de)'
}

$Domain = $Domain.Trim().ToLower() -replace '^https?://', '' -replace '/.*$', ''
if ($Domain -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$') {
    throw "Ungültige Domain: '$Domain' – bitte nur den Namen, z. B. darts.beispiel.de"
}
if ($Domain -in @('darts.example.org', 'darts.example.invalid', 'darts.beispiel.de')) {
    throw 'Das ist nur die Beispiel-Domain – bitte die echte eintragen.'
}

$text = "# Domain des Darts-Servers – eingetragen mit tool\set_domain.ps1.`n" +
        "# Wird automatisch von tool\build_release.ps1 übernommen (APK, .env.example im ZIP).`n" +
        "$Domain`n"
[System.IO.File]::WriteAllText($file, $text, $utf8)
Write-Host ''
Write-Host "Domain eingetragen: $Domain" -ForegroundColor Green
Write-Host "  App-Server:  https://$Domain"
Write-Host "  Web-App:     https://$Domain"
Write-Host "  Datei:       deploy\domain.txt"

# Nur zur Info: zeigt die Domain schon auf einen Server?
try {
    $ips = [System.Net.Dns]::GetHostAddresses($Domain) | ForEach-Object { $_.IPAddressToString }
    Write-Host "  DNS:         zeigt auf $($ips -join ', ')"
} catch {
    Write-Host '  DNS:         noch kein Eintrag gefunden (der Freund muss einen A-Eintrag auf seinen Server setzen)' -ForegroundColor Yellow
}

if ($Build) {
    Write-Host ''
    & (Join-Path $PSScriptRoot 'build_release.ps1')
    exit $LASTEXITCODE
} else {
    Write-Host ''
    Write-Host 'Nächster Schritt: APK + ZIP bauen mit'
    Write-Host '  powershell -ExecutionPolicy Bypass -File tool\build_release.ps1'
}
