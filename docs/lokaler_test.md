# Lokaler Test – Server am PC, Handys/Tablet im Heim-WLAN

Für Simon, Schritt für Schritt. Alle Befehle in **PowerShell** im Ordner `C:\dev\darts_counter`.
Die Bedien-Tests auf den Geräten machst du selbst; Claude installiert nur.

---

## 1. Web-App, APK und version.json bereitstellen

Am einfachsten über das Release-Skript (baut die Web-App und legt `version.json` an; den Server braucht es dafür nicht):

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -SkipServer
```

Danach liegen in `release\darts_server_3.0.0\` die Ordner `web\`, `apk\` und die Datei `version.json`.
(Fehlt `APK\Darts_3.0.0.apk` noch, zusätzlich `-SkipApk` angeben – dann gibt es nur keinen Update-Download.)

Ohne Skript geht es auch: `C:\dev\flutter\bin\flutter.bat build web --release` → `build\web`, APK liegt in `APK\`.
Dann aber eine eigene `version.json` anlegen (Format: `{"version":"3.0.0","build":19,"minProtocol":3,"apk":"/apk/Darts_3.0.0.apk","notes":["Test"]}`).

## 2. Server am PC starten

```powershell
cd C:\dev\darts_counter\server
C:\dev\flutter\bin\dart.bat pub get

$env:PORT = "8080"
$env:HOST = "0.0.0.0"                       # auch aus dem WLAN erreichbar
$env:WEB_DIR = "..\release\darts_server_3.0.0\web"     # oder ..\build\web
$env:APK_DIR = "..\APK"                     # enthält Darts_3.0.0.apk
$env:VERSION_FILE = "..\release\darts_server_3.0.0\version.json"
$env:LOG_LEVEL = "info"

C:\dev\flutter\bin\dart.bat run bin\server.dart
```

Das Fenster offen lassen; **Strg+C** beendet den Server. Prüfen am PC: <http://localhost:8080/health> (→ 200)
und <http://localhost:8080/version.json>.

## 3. Windows-Firewall für Port 8080 öffnen (einmalig)

Braucht **Administrator-Rechte** – den Befehl führst du selbst aus (PowerShell „Als Administrator ausführen“).
Claude setzt keine Firewall-Regeln.

```powershell
New-NetFirewallRule -DisplayName "Darts Server 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Private
```

Das Heim-WLAN muss in Windows als **privates** Netzwerk eingestuft sein (Einstellungen → Netzwerk → WLAN → Netzwerkprofil „Privat“).
Nach dem Testen wieder entfernen:

```powershell
Remove-NetFirewallRule -DisplayName "Darts Server 8080"
```

## 4. IP-Adresse des PCs herausfinden

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq 'Dhcp' } | Select-Object IPAddress, InterfaceAlias
```

(oder `ipconfig` → „IPv4-Adresse“ des WLAN-/Ethernet-Adapters, meist `192.168.x.y`). Im Folgenden `<PC-IP>`.

Test vom Handy-Browser: `http://<PC-IP>:8080/health` muss eine Antwort zeigen. Wenn nicht: Firewall (Schritt 3), gleiches WLAN?

## 5. Geräte einrichten

- **Android-APK 3.0.0:** installieren (Claude: `adb install -r APK\Darts_3.0.0.apk`).
  In der App oben auf das Koppeln-Symbol tippen, **„Online“** wählen, unten **„Erweitert“** aufklappen und die **Server-Adresse** auf `http://<PC-IP>:8080` setzen.
  (2.10.1 kennt den Server noch nicht – vorher einmal auf 3.0.0 aktualisieren.)
- **Browser** (PC: Chrome; Tablet/anderes Handy): `http://<PC-IP>:8080` öffnen – die Web-App nimmt automatisch
  ihren eigenen Server.

## 6. Testablauf

Haken setzen, Auffälligkeiten notieren.

**Online-Kopplung über den Server**
- [ ] X01 online mit 2 Geräten: Gerät A „Online → Raum öffnen“, Gerät B gibt den Raum-Code ein, A bestätigt das neue Gerät
- [ ] Dasselbe mit 3 Geräten (z. B. Chrome am PC + Handy + Tablet), Würfe von verschiedenen Geräten, Undo
- [ ] Chrome am PC als **Host** (nicht nur als Gast)
- [ ] Verbindungsabbruch: WLAN am Gast kurz aus/an → verbindet neu, Stand stimmt
- [ ] Host-App schließen und neu öffnen → Raum wird zurückgeholt, Gäste sehen „Host offline“ und danach wieder den Stand
- [ ] „Raum schließen“ am Host → Gäste bekommen eine klare Meldung
- [ ] Falscher Raum-Code → verständliche Meldung
- [ ] Training online (z. B. Checkout-Training abwechselnd)
- [ ] Kleines Turnier (3–4 Spieler) online, Ergebnisse auf allen Geräten
- [ ] Abgleich (Statistik/Spieler) zwischen gekoppelten Geräten

**Anzeige-Modus im Browser**
- [ ] Chrome am PC als Anzeige (Scoreboard) koppeln, F11/Vollbild, Spiel am Handy starten
- [ ] Turnier-Anzeige und Wartebildschirm

**Update**
- [ ] `version.json` testweise auf höheren `build` setzen (z. B. 20), APK-App neu starten → Dialog „Neue Version“, Download startet
- [ ] Web-App: nach neuem Web-Build „Neue Version – neu laden“

**WLAN-Kopplung ohne Server (Rückfallebene)**
- [ ] Server beenden (Strg+C), zwei Android-Geräte im WLAN wie bisher koppeln, X01 spielen
- [ ] Alte APK 2.10.1 ↔ neue 3.0.0 im WLAN koppeln weiterhin

Notizen:

```
 
 
```

## 7. iPhone: Home-Bildschirm und Wach-Halten brauchen HTTPS

Über `http://<PC-IP>:8080` läuft die Web-App auf dem iPhone, aber **„Zum Home-Bildschirm“ als echte App, Offline-Start,
Bildschirm-wach-halten und Speicher-Schutz gehen nur über HTTPS**. Für den Test mit dem Leihgerät deshalb kurz ein
**Cloudflare-Quick-Tunnel** (ohne Konto, kostenlos, nur solange das Fenster offen ist):

1. `cloudflared` portabel herunterladen (macht Simon selbst, Claude lädt nichts herunter):
   <https://github.com/cloudflare/cloudflared/releases/latest> → Datei **`cloudflared-windows-amd64.exe`**
   nach `C:\dev\tools\cloudflared.exe` speichern (keine Installation nötig).
2. Server wie in Schritt 2 laufen lassen.
3. In einem zweiten PowerShell-Fenster:

   ```powershell
   C:\dev\tools\cloudflared.exe tunnel --url http://localhost:8080
   ```

   Nach ein paar Sekunden erscheint eine Adresse `https://<zufall>.trycloudflare.com`.
4. Diese Adresse auf dem iPhone in **Safari** öffnen und `docs/ios_testliste.md` abarbeiten.
   Android-Geräte können für den gemeinsamen Test dieselbe `https://…`-Adresse als Server-Adresse nehmen.
5. **Nach dem Test den Tunnel beenden** (Strg+C im cloudflared-Fenster). Die Adresse ist danach tot;
   beim nächsten Start gibt es eine neue (dann am iPhone die Home-Bildschirm-App neu anlegen – Daten hängen an der Adresse!).

Hinweise:
- Solange der Tunnel läuft, ist der Server **aus dem Internet** erreichbar (unter der Zufallsadresse). Nur für die Dauer des Tests.
- Über den Tunnel kommen alle Verbindungen von `127.0.0.1`. Das Rate-Limit/die Sperre nach falschen Codes gilt dann für alle
  zusammen – bei vielen Fehlversuchen Server neu starten. (Mit `$env:TRUST_PROXY = "true"` vor dem Start nutzt der Server die
  echte IP aus dem Header von Cloudflare; danach wieder weglassen.)
- Daten der Web-App (Spieler, Statistik) liegen **pro Adresse** im Browser. Was unter `http://<PC-IP>:8080` angelegt wurde,
  ist unter der Tunnel-Adresse nicht da – zum Übertragen Backup exportieren/importieren.

## 8. Aufräumen

- Server: Strg+C
- Tunnel: Strg+C
- Firewall-Regel entfernen (Schritt 3)
- Server-Adresse in der Android-App wieder auf Standard (Produktiv-Adresse) stellen
