# NOCO RUNNING

Native iOS-Laufapp mit lokalem KI-Coach auf deinem Windows-PC.

Priorität: **Stabiles Tracking vor allem anderen.** Die KI darf einen Lauf niemals blockieren.

## Was in der Grundversion steckt

- Lauf starten, pausieren, fortsetzen, beenden
- GPS mit Glättung gegen Ausreißer
- Live-Karte, Pace, Speed-Tacho, Distanz, Zeit
- Lokale Speicherung (SwiftData) inklusive Wiederherstellung nach App-Neustart
- Live Activity / Dynamic Island
- HealthKit optional, ohne Apple Watch
- Musiksteuerung über die Systemwiedergabe
- Dashboard, Statistik, Ziele, Rekorde, Gewicht, Strecken, Import
- Coach: QR-Kopplung mit dem **NOCO RUNNING**-Plugin in NOCO AI (Port 4747), Offline-Fallback
- Health/Adidas-Import der Lauf-Historie
- Liquid Glass, Rainbow Glow, Intelligence-Animationen

## Ordner

| Pfad | Inhalt |
|---|---|
| `ios/` | Xcode-Projekt, App, Live Activity, Shared-Code, Tests |
| `server/` | Optionaler Legacy-FastAPI-Coach |
| `output/` | Zielordner für IPA / Archive |
| `scripts/` | Build- und Start-Skripte |

## iOS öffnen

Auf einem Mac:

1. `ios/NOCORunning.xcodeproj` in Xcode öffnen
2. Team unter Signing wählen (`com.noco.running`)
3. iPhone oder Simulator, Scheme **NOCORunning**
4. Erster Lauf: Standort, Kamera (QR) und optional Health erlauben

Dieses Windows-Workspace kann Swift **nicht** kompilieren. IPA kommt über GitHub Actions.

## NOCO AI koppeln (wichtig)

1. NOCO AI X auf dem Windows-PC starten (Companion `:4747`, Plugin **NOCO RUNNING** aktiv).
2. QR-Code im Companion anzeigen.
3. In der iPhone-App: **Coach → NOCO AI koppeln → QR-Code scannen**.
4. Fertig — Läufe, Analysen und Fragen gehen an den PC. Ohne Verbindung antwortet der Offline-Coach.

Firewall: TCP **4747** im privaten Netz erlauben.

## IPA auf Windows (ohne Mac)

GitHub Actions baut die IPA auf einem Mac-Runner. Danach auf dem Windows-PC:

```powershell
.\scripts\Download-IPA.ps1
```

Die Datei landet in `output\NOCORunning.ipa` und der Ordner öffnet sich. Sideloading z.B. mit Sideloadly (Apple-ID signiert lokal).

Manuell: GitHub → Actions → **Build IPA** → neuesten grünen Lauf → Artifacts → `NOCORunning-ipa`.

HealthKit und Live Activities brauchen für volle Systemintegration eine bezahlte Apple-Developer-Signierung. GPS-Tracking in NOCO läuft auch in der sideloadbaren IPA.

## Design

Liquid Glass, Rainbow Glow, Aurora-Orbs und Apple-Intelligence-Shimmer. Während eines Laufs bleiben die Animationen bewusst leichter, damit GPS nicht ruckelt.
