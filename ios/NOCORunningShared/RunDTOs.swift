import Foundation

public enum RunPhase: String, Codable, Sendable {
    case idle
    case preparing
    case running
    case paused
    case finishing
}

public struct LiveSnapshot: Sendable, Equatable {
    public var phase: RunPhase
    public var startedAt: Date?
    public var elapsed: TimeInterval
    public var movingElapsed: TimeInterval
    public var distanceMeters: Double
    public var currentSpeedMPS: Double
    public var averageSpeedMPS: Double
    public var currentPaceSecondsPerKm: Double?
    public var averagePaceSecondsPerKm: Double?
    public var elevationGainMeters: Double
    public var calories: Double?
    public var heartRate: Double?
    public var steps: Double?
    public var latitude: Double?
    public var longitude: Double?
    public var isStationary: Bool
    public var gpsReady: Bool
    public var gpsAccuracy: Double?

    public static let empty = LiveSnapshot(
        phase: .idle,
        startedAt: nil,
        elapsed: 0,
        movingElapsed: 0,
        distanceMeters: 0,
        currentSpeedMPS: 0,
        averageSpeedMPS: 0,
        currentPaceSecondsPerKm: nil,
        averagePaceSecondsPerKm: nil,
        elevationGainMeters: 0,
        calories: nil,
        heartRate: nil,
        steps: nil,
        latitude: nil,
        longitude: nil,
        isStationary: true,
        gpsReady: false,
        gpsAccuracy: nil
    )

    public init(
        phase: RunPhase,
        startedAt: Date?,
        elapsed: TimeInterval,
        movingElapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedMPS: Double,
        averageSpeedMPS: Double,
        currentPaceSecondsPerKm: Double?,
        averagePaceSecondsPerKm: Double?,
        elevationGainMeters: Double,
        calories: Double?,
        heartRate: Double?,
        steps: Double?,
        latitude: Double?,
        longitude: Double?,
        isStationary: Bool,
        gpsReady: Bool,
        gpsAccuracy: Double?
    ) {
        self.phase = phase
        self.startedAt = startedAt
        self.elapsed = elapsed
        self.movingElapsed = movingElapsed
        self.distanceMeters = distanceMeters
        self.currentSpeedMPS = currentSpeedMPS
        self.averageSpeedMPS = averageSpeedMPS
        self.currentPaceSecondsPerKm = currentPaceSecondsPerKm
        self.averagePaceSecondsPerKm = averagePaceSecondsPerKm
        self.elevationGainMeters = elevationGainMeters
        self.calories = calories
        self.heartRate = heartRate
        self.steps = steps
        self.latitude = latitude
        self.longitude = longitude
        self.isStationary = isStationary
        self.gpsReady = gpsReady
        self.gpsAccuracy = gpsAccuracy
    }
}

public struct CoordinateSample: Codable, Sendable, Hashable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var speedMPS: Double
    public var accuracy: Double

    public init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double, speedMPS: Double, accuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speedMPS = speedMPS
        self.accuracy = accuracy
    }
}

public struct SplitDTO: Codable, Sendable, Hashable {
    public var kilometerIndex: Int
    public var duration: TimeInterval
    public var paceSecondsPerKm: Double
    public var elevationDelta: Double

    public init(kilometerIndex: Int, duration: TimeInterval, paceSecondsPerKm: Double, elevationDelta: Double) {
        self.kilometerIndex = kilometerIndex
        self.duration = duration
        self.paceSecondsPerKm = paceSecondsPerKm
        self.elevationDelta = elevationDelta
    }
}

public struct RunSummaryDTO: Codable, Sendable, Hashable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var distanceMeters: Double
    public var duration: TimeInterval
    public var averagePaceSecondsPerKm: Double?
    public var averageSpeedMPS: Double
    public var calories: Double?
    public var averageHeartRate: Double?
    public var elevationGainMeters: Double
    public var weatherTempC: Double?
    public var weatherSymbol: String?
    public var source: String
    public var splits: [SplitDTO]

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        distanceMeters: Double,
        duration: TimeInterval,
        averagePaceSecondsPerKm: Double?,
        averageSpeedMPS: Double,
        calories: Double?,
        averageHeartRate: Double?,
        elevationGainMeters: Double,
        weatherTempC: Double?,
        weatherSymbol: String?,
        source: String,
        splits: [SplitDTO]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.averagePaceSecondsPerKm = averagePaceSecondsPerKm
        self.averageSpeedMPS = averageSpeedMPS
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.elevationGainMeters = elevationGainMeters
        self.weatherTempC = weatherTempC
        self.weatherSymbol = weatherSymbol
        self.source = source
        self.splits = splits
    }
}

public struct AthleteContext: Codable, Sendable {
    public var athleteName: String
    public var weightKg: Double?
    public var weekDistanceMeters: Double
    public var monthDistanceMeters: Double
    public var typicalPaceSecondsPerKm: Double?
    public var typicalDistanceMeters: Double?
    public var runCount: Int
    public var goals: [String]
    public var recentRuns: [RunSummaryDTO]
    public var question: String?
    public var locale: String

    public init(
        athleteName: String,
        weightKg: Double?,
        weekDistanceMeters: Double,
        monthDistanceMeters: Double,
        typicalPaceSecondsPerKm: Double?,
        typicalDistanceMeters: Double?,
        runCount: Int,
        goals: [String],
        recentRuns: [RunSummaryDTO],
        question: String?,
        locale: String = "de-DE"
    ) {
        self.athleteName = athleteName
        self.weightKg = weightKg
        self.weekDistanceMeters = weekDistanceMeters
        self.monthDistanceMeters = monthDistanceMeters
        self.typicalPaceSecondsPerKm = typicalPaceSecondsPerKm
        self.typicalDistanceMeters = typicalDistanceMeters
        self.runCount = runCount
        self.goals = goals
        self.recentRuns = recentRuns
        self.question = question
        self.locale = locale
    }
}

public struct CoachReply: Codable, Sendable, Equatable {
    public var title: String
    public var insight: String
    public var recommendation: String?
    public var mood: String
    public var source: String

    public init(title: String, insight: String, recommendation: String?, mood: String, source: String) {
        self.title = title
        self.insight = insight
        self.recommendation = recommendation
        self.mood = mood
        self.source = source
    }
}

public struct ImportedRunDraft: Codable, Sendable, Equatable {
    public var startedAt: Date?
    public var distanceMeters: Double?
    public var duration: TimeInterval?
    public var averagePaceSecondsPerKm: Double?
    public var averageHeartRate: Double?
    public var calories: Double?
    public var notes: String?
    public var confidence: Double

    public init(
        startedAt: Date? = nil,
        distanceMeters: Double? = nil,
        duration: TimeInterval? = nil,
        averagePaceSecondsPerKm: Double? = nil,
        averageHeartRate: Double? = nil,
        calories: Double? = nil,
        notes: String? = nil,
        confidence: Double = 0
    ) {
        self.startedAt = startedAt
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.averagePaceSecondsPerKm = averagePaceSecondsPerKm
        self.averageHeartRate = averageHeartRate
        self.calories = calories
        self.notes = notes
        self.confidence = confidence
    }
}
