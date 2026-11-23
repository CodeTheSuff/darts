@echo off
rem Doppelklick: neue Version auf GitHub veroeffentlichen (APK bauen, Release anlegen).
rem GitHub baut danach automatisch das Docker-Image fuer ghcr.io.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File tool\github_release.ps1
echo.
pause
