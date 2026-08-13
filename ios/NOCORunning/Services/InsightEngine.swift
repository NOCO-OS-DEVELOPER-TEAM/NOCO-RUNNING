import Foundation

/// Local pattern detection: one-sentence run summaries, self-questions from values, weekly rollups.
/// Never invents numbers — only uses stored run metrics. PC KI can refine later.
enum InsightEngine {
    struct SelfProbe: Equatable, Identifiable {
        var id: String { question }
        var question: String
        var hypothesis: String
    }

    static func oneSentence(for run: Run, typicalPace: Double?, typicalDistance: Double?) -> String {
        let km = run.distanceMeters / 1000
        let pace = run.averagePaceSecondsPerKm
        let paceText = pace.map { RunFormatters.paceClock($0) } ?? "–"
        var bits: [String] = [
            "\(String(format: "%.2f", km).replacingOccurrences(of: ".", with: ",")) km in \(RunFormatters.duration(run.durationSeconds)) bei Pace \(paceText)."
        ]
        if let pace, let typicalPace {
            let delta = pace - typicalPace
            if delta < -12 {
                bits.append("Deutlich flotter als dein Schnitt.")
            } else if delta > 15 {
                bits.append("Ruhiger als dein übliches Tempo.")
            }
        }
        if let typicalDistance, run.distanceMeters > typicalDistance * 1.25, run.distanceMeters > 5000 {
            bits.append("Länger als deine typische Distanz.")
        }
        if let hr = run.averageHeartRate, hr > 0 {
            bits.append("Ø Puls \(Int(hr.rounded())).")
        }
        return bits.joined(separator: " ")
    }

    static func selfProbes(from runs: [Run]) -> [SelfProbe] {
        let completed = StatsMath.completedRuns(runs)
        guard completed.count >= 2 else { return [] }
        let typicalPace = StatsMath.typicalPace(from: completed)
        let typicalDistance = StatsMath.typicalDistance(from: completed)
        var probes: [SelfProbe] = []

        let recent = Array(completed.prefix(6))
        let longFast = recent.filter { run in
            guard let pace = run.averagePaceSecondsPerKm, let typicalPace, let typicalDistance else { return false }
            return run.distanceMeters >= max(7000, typicalDistance * 1.15) && pace <= typicalPace - 8
        }
        if longFast.count >= 2, let typicalPace, let typicalDistance {
            probes.append(SelfProbe(
                question: "Warum hältst du bei langen Läufen oft ein hohes Tempo?",
                hypothesis: "In \(longFast.count) von \(recent.count) letzten Läufen warst du länger als üblich (≥ \(String(format: "%.1f", typicalDistance / 1000)) km) und gleichzeitig flotter als dein Schnitt (\(RunFormatters.paceClock(typicalPace))). Das kann Form sein — oder zu wenig echte Erholungsläufe."
            ))
        }

        let shortHard = recent.filter { run in
            guard let pace = run.averagePaceSecondsPerKm, let typicalPace else { return false }
            return run.distanceMeters < 5000 && pace < typicalPace - 20
        }
        if shortHard.count >= 2, let typicalPace {
            probes.append(SelfProbe(
                question: "Warum sind deine kurzen Läufe oft deutlich schneller?",
                hypothesis: "Mehrere kurze Einheiten liegen klar unter \(RunFormatters.paceClock(typicalPace)). Kurz und hart ist ok — aber wenn das der Standard ist, fehlt oft der lockere Basisanteil."
            ))
        }

        if let last = completed.first, let pace = last.averagePaceSecondsPerKm, let typicalPace {
            let secondHalf = last.splits.filter { $0.kilometerIndex >= 3 }
            let firstHalf = last.splits.filter { $0.kilometerIndex <= 2 }
            if let avgFirst = averagePace(firstHalf), let avgSecond = averagePace(secondHalf),
               avgSecond - avgFirst > 20 {
                probes.append(SelfProbe(
                    question: "Warum brach die zweite Hälfte beim letzten Lauf ein?",
                    hypothesis: "Start ≈ \(RunFormatters.paceClock(avgFirst)), danach ≈ \(RunFormatters.paceClock(avgSecond)) — gegenüber deinem Schnitt \(RunFormatters.paceClock(typicalPace)). Zu schneller Einstieg ist die wahrscheinlichste Erklärung aus den Splits."
                ))
            } else if pace < typicalPace - 15, last.distanceMeters > 6000 {
                probes.append(SelfProbe(
                    question: "Wie nachhaltig ist dieses Tempo über längere Distanzen?",
                    hypothesis: "Letzter Lauf: \(String(format: "%.1f", last.distanceMeters / 1000)) km bei \(RunFormatters.paceClock(pace)) vs. Schnitt \(RunFormatters.paceClock(typicalPace)). Die Werte sprechen für gute Form — prüfe, ob der nächste Lauf bewusst langsamer bleibt."
                ))
            }
        }

        let week = StatsMath.distance(completed, from: StatsMath.weekStart())
        let prevWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: StatsMath.weekStart()) ?? .now
        let prevWeek = StatsMath.distance(completed, from: prevWeekStart, to: StatsMath.weekStart())
        if prevWeek > 1000, week > prevWeek * 1.35 {
            probes.append(SelfProbe(
                question: "Warum ist dein Wochenvolumen so stark gestiegen?",
                hypothesis: "Diese Woche \(String(format: "%.1f", week / 1000)) km vs. \(String(format: "%.1f", prevWeek / 1000)) km zuvor (+ \(Int(((week / prevWeek) - 1) * 100)) %). Steile Anstiege erhöhen das Überlastungsrisiko."
            ))
        }

        var seen = Set<String>()
        return probes.filter { seen.insert($0.question).inserted }
    }

    static func weeklyOverview(from runs: [Run]) -> String {
        let completed = StatsMath.completedRuns(runs)
        let start = StatsMath.weekStart()
        let weekRuns = completed.filter { $0.startedAt >= start }
        let km = weekRuns.reduce(0.0) { $0 + $1.distanceMeters } / 1000
        let pace = StatsMath.averagePace(weekRuns, from: start)
        let paceText = pace.map { RunFormatters.paceClock($0) } ?? "–"
        var lines: [String] = [
            "Woche: \(weekRuns.count) Läufe, \(String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")) km, Ø-Pace \(paceText)."
        ]
        for run in weekRuns.prefix(8) {
            lines.append("· \(oneSentence(for: run, typicalPace: StatsMath.typicalPace(from: completed), typicalDistance: StatsMath.typicalDistance(from: completed)))")
        }
        let probes = selfProbes(from: completed)
        if let first = probes.first {
            lines.append("Selbstfrage: \(first.question) — \(first.hypothesis)")
        }
        return lines.joined(separator: "\n")
    }

    /// Prompt for the PC model: ask it to answer the self-question using numbers only.
    static func pcPrompt(for probe: SelfProbe, contextBlurb: String) -> String {
        """
        Beantworte knapp anhand der gespeicherten Laufwerte (keine erfundenen Stats):
        Selbstfrage: \(probe.question)
        Lokale Hypothese aus den Werten: \(probe.hypothesis)
        Kontext: \(contextBlurb)
        Gib 2–4 Sätze: Ursache nach den Daten, und einen konkreten nächsten Schritt.
        """
    }

    private static func averagePace(_ splits: [Split]) -> Double? {
        guard !splits.isEmpty else { return nil }
        return splits.reduce(0.0) { $0 + $1.paceSecondsPerKm } / Double(splits.count)
    }
}
