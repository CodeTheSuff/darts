@echo off
rem Doppelklick: Domain des Darts-Servers eintragen und auf Wunsch gleich APK + ZIP bauen.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File tool\set_domain.ps1
if errorlevel 1 goto ende
echo.
set /p BAU="Jetzt APK und ZIP fuer den Freund bauen? (j/n) "
if /i "%BAU%"=="j" powershell -NoProfile -ExecutionPolicy Bypass -File tool\build_release.ps1
:ende
echo.
pause
