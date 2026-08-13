import Foundation

enum PersonalizedQuestions {
    static func make(from runs: [Run], weekMeters: Double, remote: [String] = []) -> [String] {
        let completed = StatsMath.completedRuns(runs)
        var items: [String] = []

        // Prefer live questions from the PC feed (always freshest when synced).
        items.append(contentsOf: remote.prefix(8))

        for probe in InsightEngine.selfProbes(from: completed) {
            items.append(probe.question)
        }

        if let last = completed.first {
            let km = String(format: "%.2f", last.distanceMeters / 1000)
            let pace = RunFormatters.paceClock(last.averagePaceSecondsPerKm ?? 0)
            items.append("Wie war mein letzter Lauf (\(km) km, Pace \(pace))?")
            items.append("Fasse meinen letzten Lauf in einem Satz zusammen und stelle eine Selbstfrage dazu.")
            if last.splits.count >= 2 {
                items.append("Warum war meine zweite Hälfte beim letzten Lauf anders als der Start?")
            }
            if last.source == .appleHealth {
                items.append("Was sagst du zu meinem Adidas-/Watch-Lauf vom \(RunFormatters.relativeDate(last.startedAt))?")
            }
        }

        let weekKm = weekMeters / 1000
        items.append("Ich bin diese Woche \(String(format: "%.1f", weekKm)) km gelaufen — was sollte ich als Nächstes machen?")
        items.append("Fasse meine Woche in 4 Sätzen zusammen und stelle dir eine Selbstfrage zu meinem Tempo/Volumen.")

        if let typical = StatsMath.typicalPace(from: completed) {
            items.append("Mein typisches Tempo ist \(RunFormatters.paceClock(typical)) min/km. Wie werde ich nachhaltig schneller?")
        }

        if completed.count >= 3 {
            items.append("Wie hat sich meine Leistung über die letzten \(min(completed.count, 8)) Läufe entwickelt?")
            items.append("Welche Schwachstelle fällt in meinen Statistiken am klarsten auf?")
        } else {
            items.append("Wie oft sollte ich aktuell laufen?")
            items.append("Wie lang sollte ein lockerer Lauf für mich sein?")
        }

        items.append("Was war mein bester Lauf und warum?")
        items.append("Wie verbessere ich meine Ausdauer ohne mich zu überlasten?")

        var seen = Set<String>()
        return items.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted }
    }
}
