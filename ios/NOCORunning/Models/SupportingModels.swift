import Foundation
import SwiftData

@Model
final class WeightEntry {
    var date: Date
    var kilograms: Double
    var note: String?

    init(date: Date = .now, kilograms: Double, note: String? = nil) {
        self.date = date
        self.kilograms = kilograms
        self.note = note
    }
}

@Model
final class SavedRoute {
    var id: UUID
    var name: String
    var createdAt: Date
    var distanceMeters: Double
    var isFavorite: Bool
    var encodedCoordinates: Data
    var lastUsedAt: Date?

    init(name: String, distanceMeters: Double, coordinates: [CoordinateSample], isFavorite: Bool = false) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.distanceMeters = distanceMeters
        self.isFavorite = isFavorite
        self.encodedCoordinates = (try? JSONEncoder().encode(coordinates)) ?? Data()
    }

    var coordinates: [CoordinateSample] {
        (try? JSONDecoder().decode([CoordinateSample].self, from: encodedCoordinates)) ?? []
    }
}

enum GoalKind: String, Codable, CaseIterable, Identifiable {
    case weeklyDistance
    case monthlyDistance
    case weeklyRuns
    case targetPace
    case targetDistance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklyDistance: return "Kilometer / Woche"
        case .monthlyDistance: return "Kilometer / Monat"
        case .weeklyRuns: return "Läufe / Woche"
        case .targetPace: return "Ziel-Pace"
        case .targetDistance: return "Distanzziel"
        }
    }
}

@Model
final class Goal {
    var kindRaw: String
    var targetValue: Double
    var createdAt: Date
    var isActive: Bool

    init(kind: GoalKind, targetValue: Double) {
        self.kindRaw = kind.rawValue
        self.targetValue = targetValue
        self.createdAt = .now
        self.isActive = true
    }

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .weeklyDistance }
        set { kindRaw = newValue.rawValue }
    }
}

enum RecordKind: String, Codable, CaseIterable {
    case longestRun
    case fastestRun
    case bestPace
    case fastestKilometer
    case bestWeek
    case bestMonth

    var title: String {
        switch self {
        case .longestRun: return "Längster Lauf"
        case .fastestRun: return "Schnellster Lauf"
        case .bestPace: return "Beste Pace"
        case .fastestKilometer: return "Schnellster Kilometer"
        case .bestWeek: return "Beste Woche"
        case .bestMonth: return "Bester Monat"
        }
    }
}

@Model
final class PersonalRecord {
    var kindRaw: String
    var value: Double
    var achievedAt: Date
    var runID: UUID?
    var celebrated: Bool

    init(kind: RecordKind, value: Double, achievedAt: Date, runID: UUID? = nil) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.achievedAt = achievedAt
        self.runID = runID
        self.celebrated = false
    }

    var kind: RecordKind {
        get { RecordKind(rawValue: kindRaw) ?? .longestRun }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var createdAt: Date
    var isUser: Bool
    var text: String

    init(isUser: Bool, text: String) {
        self.id = UUID()
        self.createdAt = .now
        self.isUser = isUser
        self.text = text
    }
}
