import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String
    var preferredUnitsRaw: String
    var weeklyDistanceGoalMeters: Double
    var animationsEnabled: Bool
    var reduceMotionOverride: Bool

    init(name: String = "") {
        self.name = name
        self.preferredUnitsRaw = UnitSystem.metric.rawValue
        self.weeklyDistanceGoalMeters = 20_000
        self.animationsEnabled = true
        self.reduceMotionOverride = false
    }

    var units: UnitSystem {
        get { UnitSystem(rawValue: preferredUnitsRaw) ?? .metric }
        set { preferredUnitsRaw = newValue.rawValue }
    }
}

enum Persistence {
    static let schema = Schema([
        Run.self,
        TrackPoint.self,
        Split.self,
        WeightEntry.self,
        SavedRoute.self,
        Goal.self,
        PersonalRecord.self,
        ChatMessage.self,
        UserProfile.self
    ])

    static func container() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
