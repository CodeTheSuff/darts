<#
.SYNOPSIS
  Neue Version auf GitHub veröffentlichen: APK lokal bauen, Tag + Release anlegen.
  GitHub Actions baut daraufhin das Docker-Image und legt es nach ghcr.io (siehe .github/workflows/release.yml).

.DESCRIPTION
  1. Prüft: gh angemeldet, Arbeitsstand sauber, Version aus pubspec.yaml noch nicht veröffentlicht
  2. Tests (flutter test) – mit -SkipTests überspringen
  3. Release-APK bauen (Schlüssel bleibt auf diesem Laptop) -> APK\Darts_<version>.apk
  4. main + Tag v<version> pushen, GitHub-Release mit der APK anlegen (Notizen aus about_screen.dart)

  Aufruf (oder Doppelklick auf Release_veroeffentlichen.cmd):
    powershell -ExecutionPolicy Bypass -File tool\github_release.ps1
#>
[CmdletBinding()]
param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
# Ausgaben von python/git als UTF-8 lesen (sonst kaputte Umlaute in den Release-Notizen)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$flutter = 'C:\dev\flutter\bin\flutter.bat'
Set-Location $root

function Write-Step([string]$t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Invoke-Checked([string]$exe, [string[]]$a) {
    & $exe @a
    if ($LASTEXITCODE -ne 0) { throw "Fehlgeschlagen: $exe $($a -join ' ')" }
}

Write-Step 'Voraussetzungen'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) fehlt: winget install GitHub.cli' }
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'Nicht bei GitHub angemeldet: gh auth login' }
if (-not (Test-Path 'android\key.properties')) { throw 'android\key.properties fehlt – ohne Release-Schlüssel keine APK.' }
$dirty = git status --porcelain --untracked-files=no
if ($dirty) { throw "Es gibt noch nicht gespeicherte Änderungen:`n$dirty`nErst committen." }
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { throw "Bitte auf dem Branch main veröffentlichen (aktuell: $branch)." }

$version = (python tool/ci/version_json.py --print-version).Trim()
$tag = "v$version"
git rev-parse -q --verify "refs/tags/$tag" *> $null
if ($LASTEXITCODE -eq 0) { throw "Tag $tag gibt es schon – erst die Version in pubspec.yaml (und about_screen.dart) erhöhen." }
Write-Host "Version $version"

if (-not $SkipTests) {
    Write-Step 'Tests'
    Invoke-Checked $flutter @('test')
}

Write-Step 'Release-APK bauen'
Invoke-Checked $flutter @('build', 'apk', '--release')
$apk = "APK\Darts_$version.apk"
New-Item -ItemType Directory -Force -Path APK | Out-Null
Copy-Item -Force 'build\app\outputs\flutter-apk\app-release.apk' $apk
Write-Host "APK: $apk"

Write-Step 'Hochladen (main + Tag)'
Invoke-Checked git @('push', 'origin', 'main')
Invoke-Checked git @('tag', '-a', $tag, '-m', "Darts $version")
Invoke-Checked git @('push', 'origin', $tag)

Write-Step 'GitHub-Release anlegen'
$info = python tool/ci/version_json.py | Out-String | ConvertFrom-Json
$notes = ($info.notes | ForEach-Object { "- $_" }) -join "`n"
$notesFile = Join-Path $env:TEMP "darts_release_notes.md"
[System.IO.File]::WriteAllText($notesFile, "## Neu in $version`n`n$notes`n", (New-Object System.Text.UTF8Encoding($false)))
Invoke-Checked gh @('release', 'create', $tag, $apk, '--title', "Darts $version", '--notes-file', $notesFile)
Remove-Item $notesFile -ErrorAction SilentlyContinue

$repo = (gh repo view --json nameWithOwner -q .nameWithOwner).Trim()
Write-Host ''
Write-Host "Fertig: Release $tag ist angelegt." -ForegroundColor Green
Write-Host "GitHub baut jetzt das Docker-Image (ca. 10 Minuten): https://github.com/$repo/actions"
Write-Host "Danach: ghcr.io/$($repo.Split('/')[0].ToLower())/darts:$version und :latest"
