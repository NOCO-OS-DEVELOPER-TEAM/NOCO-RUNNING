from __future__ import annotations

import os
import re
from datetime import datetime, timezone
from typing import Any, Optional

import httpx
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

TOKEN = os.getenv("NOCO_API_TOKEN", "").strip()
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.1")

app = FastAPI(title="NOCO RUNNING Coach", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class SplitDTO(BaseModel):
    kilometerIndex: int
    duration: float
    paceSecondsPerKm: float
    elevationDelta: float = 0


class RunSummaryDTO(BaseModel):
    id: str
    startedAt: datetime
    endedAt: Optional[datetime] = None
    distanceMeters: float
    duration: float
    averagePaceSecondsPerKm: Optional[float] = None
    averageSpeedMPS: float = 0
    calories: Optional[float] = None
    averageHeartRate: Optional[float] = None
    elevationGainMeters: float = 0
    weatherTempC: Optional[float] = None
    weatherSymbol: Optional[str] = None
    source: str = "tracked"
    splits: list[SplitDTO] = Field(default_factory=list)


class AthleteContext(BaseModel):
    athleteName: str = ""
    weightKg: Optional[float] = None
    weekDistanceMeters: float = 0
    monthDistanceMeters: float = 0
    typicalPaceSecondsPerKm: Optional[float] = None
    typicalDistanceMeters: Optional[float] = None
    runCount: int = 0
    goals: list[str] = Field(default_factory=list)
    recentRuns: list[RunSummaryDTO] = Field(default_factory=list)
    question: Optional[str] = None
    locale: str = "de-DE"


class AnalyzeBody(BaseModel):
    run: RunSummaryDTO
    context: AthleteContext


class CoachReply(BaseModel):
    title: str
    insight: str
    recommendation: Optional[str] = None
    mood: str
    source: str


class ImportPayload(BaseModel):
    text: str


class ImportedRunDraft(BaseModel):
    startedAt: Optional[datetime] = None
    distanceMeters: Optional[float] = None
    duration: Optional[float] = None
    averagePaceSecondsPerKm: Optional[float] = None
    averageHeartRate: Optional[float] = None
    calories: Optional[float] = None
    notes: Optional[str] = None
    confidence: float = 0


class RecommendHint(BaseModel):
    message: str


def require_auth(authorization: Optional[str]) -> None:
    if not TOKEN:
        return
    expected = f"Bearer {TOKEN}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="Ungültiges Token")


def pace_clock(seconds: Optional[float]) -> str:
    if not seconds or seconds <= 0 or seconds >= 3600:
        return "–"
    total = int(round(seconds))
    return f"{total // 60}:{total % 60:02d}"


def heuristic_analyze(run: RunSummaryDTO, context: AthleteContext) -> CoachReply:
    distance_km = run.distanceMeters / 1000
    lines: list[str] = []
    mood = "steady"
    recommendation = None
    if run.averagePaceSecondsPerKm and context.typicalPaceSecondsPerKm:
        delta = run.averagePaceSecondsPerKm - context.typicalPaceSecondsPerKm
        if delta > 15:
            lines.append(
                f"Deine Pace war heute {pace_clock(run.averagePaceSecondsPerKm)} min/km — "
                f"etwas ruhiger als dein Schnitt von {pace_clock(context.typicalPaceSecondsPerKm)}."
            )
            mood = "calm"
            recommendation = "Starte die ersten zwei Kilometer bewusst locker."
        elif delta < -12:
            lines.append("Du warst heute spürbar flotter als sonst.")
            mood = "strong"
            recommendation = "Nächster Lauf bewusst locker, damit sich das Tempo setzt."
    if not lines:
        minutes = int(run.duration // 60)
        seconds = int(run.duration % 60)
        lines.append(f"Sauberer Lauf über {distance_km:.2f} km in {minutes}:{seconds:02d}.")
    week_km = context.weekDistanceMeters / 1000
    lines.append(f"Diese Woche stehen {week_km:.1f} km in deinem Log.")
    return CoachReply(
        title="Dein Lauf",
        insight=" ".join(lines),
        recommendation=recommendation,
        mood=mood,
        source="heuristic",
    )


def heuristic_chat(context: AthleteContext) -> CoachReply:
    question = (context.question or "").lower()
    week_km = context.weekDistanceMeters / 1000
    if "woche" in question or "weit" in question:
        return CoachReply(
            title="Diese Woche",
            insight=f"Du bist diese Woche {week_km:.1f} km gelaufen, bei {context.runCount} gespeicherten Läufen.",
            recommendation="Eine lockere 4-km-Runde hält den Rhythmus, ohne dich leer zu machen.",
            mood="steady",
            source="heuristic",
        )
    if context.recentRuns:
        return heuristic_analyze(context.recentRuns[0], context)
    return CoachReply(
        title="Coach",
        insight="Sobald echte Läufe gespeichert sind, kann ich sie einordnen. Ich erfinde keine Zahlen.",
        recommendation="Starte einen Lauf oder importiere ältere Daten.",
        mood="steady",
        source="heuristic",
    )


def heuristic_route(context: AthleteContext) -> str:
    week_km = context.weekDistanceMeters / 1000
    if week_km >= 12:
        return f"Du bist diese Woche schon {week_km:.1f} km gelaufen. Eine lockere 4-km-Runde wäre heute passend."
    if week_km < 4:
        return "Ein Einstieg über 3 oder 5 km hält die Woche leicht und machbar."
    return "5 km sind ein solider nächster Schritt."


def parse_import(text: str) -> ImportedRunDraft:
    raw = text.lower().replace(",", ".")
    draft = ImportedRunDraft(notes=text.strip(), confidence=0.2)
    km = re.search(r"(\d+(?:\.\d+)?)\s*km", raw)
    if km:
        draft.distanceMeters = float(km.group(1)) * 1000
    minutes = re.search(r"(\d+)\s*min", raw)
    clock = re.search(r"(\d+):(\d{2})", raw)
    if minutes:
        draft.duration = float(minutes.group(1)) * 60
    elif clock:
        draft.duration = float(clock.group(1)) * 60 + float(clock.group(2))
    pace = re.search(r"(?:pace\s*)?(\d+):(\d{2})\s*(?:min/?km)?", raw)
    if pace and "pace" in raw:
        draft.averagePaceSecondsPerKm = float(pace.group(1)) * 60 + float(pace.group(2))
    if draft.distanceMeters and draft.duration and not draft.averagePaceSecondsPerKm:
        draft.averagePaceSecondsPerKm = draft.duration / (draft.distanceMeters / 1000)
    score = 0.15
    if draft.distanceMeters:
        score += 0.35
    if draft.duration:
        score += 0.3
    if draft.averagePaceSecondsPerKm:
        score += 0.15
    draft.confidence = min(score, 0.95)
    draft.startedAt = datetime.now(timezone.utc)
    return draft


async def ollama_complete(system: str, user: str) -> Optional[str]:
    payload = {
        "model": OLLAMA_MODEL,
        "stream": False,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }
    try:
        async with httpx.AsyncClient(timeout=12) as client:
            response = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)
            response.raise_for_status()
            return response.json().get("message", {}).get("content")
    except Exception:
        return None


SYSTEM_PROMPT = """Du bist der lokale Laufcoach von NOCO RUNNING.
Antworte auf Deutsch, knapp, konkret und nur auf Basis der gelieferten JSON-Daten.
Erfinde niemals Distanz, Pace, Zeit oder Rekorde.
Wenn Daten fehlen, sag das ehrlich.
Keine medizinischen Diagnosen."""


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"ok": True, "service": "noco-running-coach", "ollama": OLLAMA_MODEL}


@app.post("/v1/analyze", response_model=CoachReply)
async def analyze(body: AnalyzeBody, authorization: Optional[str] = Header(default=None)) -> CoachReply:
    require_auth(authorization)
    fallback = heuristic_analyze(body.run, body.context)
    llm = await ollama_complete(SYSTEM_PROMPT, body.model_dump_json())
    if not llm:
        return fallback
    fallback.insight = llm.strip()
    fallback.source = "ollama"
    return fallback


@app.post("/v1/chat", response_model=CoachReply)
async def chat(context: AthleteContext, authorization: Optional[str] = Header(default=None)) -> CoachReply:
    require_auth(authorization)
    fallback = heuristic_chat(context)
    llm = await ollama_complete(SYSTEM_PROMPT, context.model_dump_json())
    if not llm:
        return fallback
    fallback.insight = llm.strip()
    fallback.source = "ollama"
    return fallback


@app.post("/v1/import", response_model=ImportedRunDraft)
async def import_run(payload: ImportPayload, authorization: Optional[str] = Header(default=None)) -> ImportedRunDraft:
    require_auth(authorization)
    return parse_import(payload.text)


@app.post("/v1/recommend", response_model=RecommendHint)
async def recommend(context: AthleteContext, authorization: Optional[str] = Header(default=None)) -> RecommendHint:
    require_auth(authorization)
    return RecommendHint(message=heuristic_route(context))
