import Foundation

public enum LocalRunImporter: Sendable {
    public static func parse(_ raw: String, now: Date = .now) -> ImportedRunDraft {
        let text = raw.lowercased().replacingOccurrences(of: ",", with: ".")
        var draft = ImportedRunDraft(notes: raw.trimmingCharacters(in: .whitespacesAndNewlines), confidence: 0.2)

        draft.distanceMeters = firstMatch(in: text, patterns: [
            #"(\d+(?:\.\d+)?)\s*km"#,
            #"(\d+(?:\.\d+)?)\s*kilometer"#
        ]).map { $0 * 1000 }

        if draft.distanceMeters == nil, let miles = firstMatch(in: text, patterns: [#"(\d+(?:\.\d+)?)\s*mi(?:les)?"#]) {
            draft.distanceMeters = miles * 1609.344
        }

        if let duration = parseDuration(text) {
            draft.duration = duration
        }

        if let pace = parsePace(text) {
            draft.averagePaceSecondsPerKm = pace
        } else if let meters = draft.distanceMeters, let duration = draft.duration {
            draft.averagePaceSecondsPerKm = PaceMath.secondsPerKm(distanceMeters: meters, duration: duration)
        }

        if draft.duration == nil, let meters = draft.distanceMeters, let pace = draft.averagePaceSecondsPerKm {
            draft.duration = pace * (meters / 1000)
        }

        if let hr = firstMatch(in: text, patterns: [#"(\d{2,3})\s*(?:bpm|hf|herz)"#]) {
            draft.averageHeartRate = hr
        }

        draft.startedAt = parseDate(text, now: now) ?? Calendar.current.startOfDay(for: now)

        var score = 0.15
        if draft.distanceMeters != nil { score += 0.35 }
        if draft.duration != nil { score += 0.3 }
        if draft.averagePaceSecondsPerKm != nil { score += 0.15 }
        if draft.averageHeartRate != nil { score += 0.05 }
        draft.confidence = min(score, 0.95)
        return draft
    }

    private static func firstMatch(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return Double(text[range])
            }
        }
        return nil
    }

    private static func parseDuration(_ text: String) -> TimeInterval? {
        let patterns = [
            #"(\d+)\s*(?:h|std)\s*(\d+)\s*min"#,
            #"(\d+)\s*min(?:uten)?\s*(\d+)\s*sek"#,
            #"(\d+):(\d{2}):(\d{2})"#,
            #"(\d+):(\d{2})"#,
            #"(\d+)\s*min"#
        ]
        if let regex = try? NSRegularExpression(pattern: patterns[0]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let h = capture(match, 1, text), let m = capture(match, 2, text) {
            return h * 3600 + m * 60
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+):(\d{2}):(\d{2})"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let h = capture(match, 1, text), let m = capture(match, 2, text), let s = capture(match, 3, text) {
            return h * 3600 + m * 60 + s
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*min(?:uten)?\s*(?:(\d+)\s*(?:s|sek))?"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let m = capture(match, 1, text) {
            let s = match.numberOfRanges > 2 ? capture(match, 2, text) ?? 0 : 0
            return m * 60 + s
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+):(\d{2})"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let m = capture(match, 1, text), let s = capture(match, 2, text), m < 180 {
            return m * 60 + s
        }
        return nil
    }

    private static func parsePace(_ text: String) -> Double? {
        let patterns = [
            #"(\d+):(\d{2})\s*(?:min\/km|min/km|min km|pace)"#,
            #"(?:min\/km|min/km|pace)\s*(\d+):(\d{2})"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let m = capture(match, 1, text), let s = capture(match, 2, text) {
                return m * 60 + s
            }
        }
        return nil
    }

    private static func parseDate(_ text: String, now: Date) -> Date? {
        if text.contains("heute") { return now }
        if text.contains("gestern") { return Calendar.current.date(byAdding: .day, value: -1, to: now) }
        let pattern = #"(\d{1,2})\.(\d{1,2})\.(\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let d = capture(match, 1, text), let m = capture(match, 2, text), let y = capture(match, 3, text) else { return nil }
        var year = Int(y)
        if year < 100 { year += 2000 }
        return Calendar.current.date(from: DateComponents(year: year, month: Int(m), day: Int(d)))
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, _ text: String) -> Double? {
        guard match.numberOfRanges > index, let range = Range(match.range(at: index), in: text) else { return nil }
        return Double(text[range])
    }
}
