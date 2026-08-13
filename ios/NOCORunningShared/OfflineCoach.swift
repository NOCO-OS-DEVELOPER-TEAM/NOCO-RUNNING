import Foundation

public enum OfflineCoach: Sendable {
    public static func analyze(run: RunSummaryDTO, context: AthleteContext) -> CoachReply {
        let distanceKm = run.distanceMeters / 1000
        let pace = run.averagePaceSecondsPerKm
        let typical = context.typicalPaceSecondsPerKm
        var lines: [String] = []
        var mood = "steady"
        var recommendation: String?

        if let pace, let typical {
            let delta = pace - typical
            if delta > 15 {
                lines.append("Deine Pace war heute \(RunFormatters.paceClock(pace)) min/km — etwas ruhiger als dein Schnitt von \(RunFormatters.paceClock(typical)).")
                mood = "calm"
                recommendation = "Wenn du nächstes Mal etwas schneller willst, starte die ersten zwei Kilometer bewusst locker und ziehe erst danach an."
            } else if delta < -12 {
                lines.append("Du warst heute spürbar flotter als sonst (\(RunFormatters.paceClock(pace)) vs. \(RunFormatters.paceClock(typical)) min/km).")
                mood = "strong"
                recommendation = "Gute Form. Achte darauf, dass der nächste Lauf wirklich locker bleibt, damit sich das Tempo setzt."
            }
        }

        if let last = context.recentRuns.dropFirst().first {
            let extra = run.distanceMeters - last.distanceMeters
            if extra > 400 {
                lines.append("Dafür bist du \(String(format: "%.1f", extra / 1000)) km weiter gelaufen als beim letzten Mal.")
            }
        }

        if let splits = fastestSlowest(run.splits) {
            if splits.slow.paceSecondsPerKm - splits.fast.paceSecondsPerKm > 25, splits.fast.kilometerIndex <= 2 {
                lines.append("Die ersten Kilometer waren deutlich schneller als der Rest. Ein ruhigerer Start würde die zweite Hälfte oft stabiler machen.")
                mood = "coach"
                recommendation = "Ziel: ersten Kilometer 10–15 Sekunden langsamer als dein Wunschschnitt."
            }
        }

        if lines.isEmpty {
            lines.append("Sauberer Lauf über \(String(format: "%.2f", distanceKm)) km in \(RunFormatters.duration(run.duration)).")
        }

        let weekKm = context.weekDistanceMeters / 1000
        lines.append("Diese Woche stehen \(String(format: "%.1f", weekKm)) km in deinem Log.")

        return CoachReply(
            title: title(for: mood, distanceKm: distanceKm),
            insight: lines.joined(separator: " "),
            recommendation: recommendation,
            mood: mood,
            source: "offline"
        )
    }

    public static func answer(question: String, context: AthleteContext) -> CoachReply {
        let q = question.lowercased()
        let weekKm = context.weekDistanceMeters / 1000
        let count = context.runCount

        if q.contains("woche") || q.contains("weit") {
            return CoachReply(
                title: "Diese Woche",
                insight: "Du bist diese Woche \(String(format: "%.1f", weekKm)) km gelaufen, bei insgesamt \(count) gespeicherten Läufen.",
                recommendation: weekKm < 8 ? "Eine lockere Runde von 3–5 km würde die Woche gut ergänzen." : "Du bist schon gut unterwegs. Ein lockerer Abschluss reicht oft.",
                mood: "steady",
                source: "offline"
            )
        }

        if q.contains("pace") || q.contains("langsamer") || q.contains("schneller") {
            let paceText = context.typicalPaceSecondsPerKm.map { RunFormatters.paceClock($0) } ?? "–"
            return CoachReply(
                title: "Pace",
                insight: "Dein typisches Tempo liegt bei etwa \(paceText) min/km, bei einer üblichen Distanz von \(String(format: "%.1f", (context.typicalDistanceMeters ?? 0) / 1000)) km.",
                recommendation: "Schneller wirst du meist nicht durch jeden Lauf hart, sondern durch lockere Kilometer plus gelegentliche etwas zügigere Abschnitte.",
                mood: "coach",
                source: "offline"
            )
        }

        if q.contains("bester") || q.contains("rekord") {
            let best = context.recentRuns.max(by: { $0.distanceMeters < $1.distanceMeters })
            let text = best.map { "Dein längster gespeicherter Lauf ist \(String(format: "%.2f", $0.distanceMeters / 1000)) km am \(RunFormatters.relativeDate($0.startedAt))." }
                ?? "Es sind noch keine Läufe gespeichert."
            return CoachReply(title: "Rekorde", insight: text, recommendation: nil, mood: "strong", source: "offline")
        }

        if let latest = context.recentRuns.first {
            return analyze(run: latest, context: context)
        }

        return CoachReply(
            title: "Coach",
            insight: "Sobald du den ersten Lauf gespeichert hast, kann ich ihn mit deinen echten Zahlen einordnen.",
            recommendation: "Starte einen Lauf oder importiere ältere Daten.",
            mood: "steady",
            source: "offline"
        )
    }

    public static func routeHint(context: AthleteContext) -> String {
        let weekKm = context.weekDistanceMeters / 1000
        if weekKm >= 12 {
            return "Du bist diese Woche schon \(String(format: "%.1f", weekKm)) km gelaufen. Eine lockere 4-km-Runde wäre heute passend."
        }
        if weekKm < 4 {
            return "Ein Einstieg über 3 oder 5 km hält die Woche leicht und machbar."
        }
        return "5 km sind ein solider nächster Schritt — weit genug für Rhythmus, kurz genug zum Erholen."
    }

    private static func title(for mood: String, distanceKm: Double) -> String {
        switch mood {
        case "strong": return "Starke Einheit"
        case "calm": return "Ruhiger Lauf"
        case "coach": return "Hinweis zum Tempo"
        default: return distanceKm >= 8 ? "Langer Lauf" : "Dein Lauf"
        }
    }

    private static func fastestSlowest(_ splits: [SplitDTO]) -> (fast: SplitDTO, slow: SplitDTO)? {
        guard splits.count >= 2 else { return nil }
        guard let fast = splits.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }),
              let slow = splits.max(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }) else { return nil }
        return (fast, slow)
    }
}
