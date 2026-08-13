# NOCO RUNNING Coach

Lokaler HTTP-Server für die iOS-App. Läuft auf deinem Windows-PC. Ohne diesen Server funktioniert das Lauftracking trotzdem — der Coach fällt dann auf den Offline-Modus zurück.

## Start

```powershell
cd "C:\Users\noah_\NOCO RUNNING\server"
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
python -m uvicorn app:app --host 0.0.0.0 --port 8787
```

Optional: [Ollama](https://ollama.com) mit einem lokalen Modell. Fehlt Ollama, antwortet ein heuristischer Coach auf Basis der echten Laufdaten.

## Firewall

Windows-Firewall: Port **8787** für private Netze zulassen.

In der App unter **Mehr → Einstellungen → Lokale Verbindung** die IPv4-Adresse dieses PCs eintragen.

## Endpunkte

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/health` | Verbindungscheck |
| POST | `/v1/analyze` | Laufanalyse |
| POST | `/v1/chat` | Assistent |
| POST | `/v1/import` | Text → Laufentwurf |
| POST | `/v1/recommend` | Streckenvorschlag |

Setze `NOCO_API_TOKEN`, wenn du ein Bearer-Token willst. Die App speichert das Token in der iOS-Keychain, nicht im Klartext-Repo.
