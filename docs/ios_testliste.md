# iPhone-Testliste (Leihgerät)

Vorbereitung: Server am PC + Cloudflare-Quick-Tunnel läuft (siehe `docs/lokaler_test.md`, Abschnitt 7).
Mindestens ein Android-Gerät mit APK 3.0.0 bereitlegen (Server-Adresse = Tunnel-Adresse).

| | |
|---|---|
| Datum | |
| iPhone-Modell | |
| iOS-Version | |
| Tunnel-Adresse | `https://…trycloudflare.com` |
| App-Version (Über) | 3.0.0 |

Legende: `[x]` geht · `[-]` geht nicht (Notiz!) · `[?]` unklar

---

## 1. Öffnen und installieren

- [ ] Tunnel-Adresse in **Safari** öffnen – App lädt, Logo/Name „Darts“ stimmen
- [ ] Hinweis „Zum Home-Bildschirm hinzufügen“ erscheint (nur in Safari, nicht installiert) und ist verständlich
- [ ] Teilen → **Zum Home-Bildschirm** → Symbol (Darts-Logo, nicht Screenshot) und Name „Darts“ stimmen
- [ ] Start vom Home-Bildschirm: **Vollbild**, keine Safari-Leisten
- [ ] Hinweis „Zum Home-Bildschirm“ erscheint in der installierten App **nicht** mehr
- [ ] Statusleiste/Farben passen (hell/dunkel)

Notizen:
```
 
```

## 2. Darstellung

- [ ] **Notch / Dynamic Island / Safe-Area:** oben nichts verdeckt, unten nichts unter dem Home-Balken
- [ ] **Drehen** hoch ↔ quer: Layout passt sich an, nichts abgeschnitten, kein „Springen“ der Höhe (100vh-Problem)
- [ ] Tastatur bei Namenseingabe schiebt nichts kaputt
- [ ] Scrollen flüssig, kein ungewolltes Zoomen bei Doppeltipp

Notizen:
```
 
```

## 3. Bedienung, Ton, Bildschirm

- [ ] X01 lokal (ohne Kopplung) starten, ein paar Aufnahmen eintragen, Undo
- [ ] **Ton:** nach dem ersten Tippen kommen Ansagen/Sounds (vorher still ist ok)
- [ ] Stummschalter am iPhone: Verhalten notieren
- [ ] **Bildschirm bleibt an** während eines Spiels (≥ 2 Minuten nichts tippen)
- [ ] Vibration fehlt – aber keine Fehlermeldung
- [ ] Training und ein Minispiel kurz anspielen
- [ ] Statistik-Seiten öffnen

Notizen:
```
 
```

## 4. Online spielen

- [ ] iPhone **hostet** einen Online-Raum, Raum-Code wird angezeigt
- [ ] Android tritt mit dem Code bei, iPhone fragt nach Erlaubnis, bestätigen
- [ ] X01 gemeinsam: Würfe von beiden Geräten, Stand überall gleich
- [ ] iPhone **als Gast** in einem Android-Raum (Android hostet)
- [ ] iPhone-App in den Hintergrund (Home-Taste), 30 s warten, zurück → verbindet neu, Stand stimmt
- [ ] iPhone-WLAN aus → mobile Daten → Verbindung kommt wieder
- [ ] Kleines Turnier online (iPhone dabei)

Notizen:
```
 
```

## 5. Anzeige-Modus

- [ ] iPhone (oder iPad) als **Anzeige** koppeln, Spiel am Android starten → Scoreboard im Vollbild
- [ ] Wartebildschirm (schwarz mit Logo) und Turnier-Anzeige
- [ ] Querformat

Notizen:
```
 
```

## 6. Daten und Backup

- [ ] **Backup exportieren** → Datei wird gespeichert (Dateien-App / Teilen-Dialog)
- [ ] App-Daten in der Home-Bildschirm-App löschen bzw. Backup in Safari (andere Speicherwelt) **importieren** → Spieler/Statistik da
- [ ] App komplett schließen (wegwischen) und neu öffnen → Daten noch da
- [ ] Erinnerung ans Backup erscheint (ggf. Zeitpunkt notieren)

Notizen:
```
 
```

## 7. Offline und Update

- [ ] Home-Bildschirm-App einmal geöffnet → **Flugmodus an** → App neu starten → startet **offline**, lokales Spiel geht
- [ ] Online-Teil zeigt offline eine verständliche Meldung
- [ ] **Update-Hinweis:** am PC neuen Web-Build einspielen (oder `version.json` hochzählen) → in der App erscheint
      „Neue Version – neu laden“, nach Tippen ist die neue Version aktiv (Über-Seite)

Notizen:
```
 
```

## 8. Gesamteindruck

```
 
 
 
```

Nach dem Test: **Tunnel beenden** (Strg+C), Home-Bildschirm-Symbol auf dem Leihgerät wieder löschen.
