import Foundation
import SwiftData

enum RunStatus: String, Codable {
    case active
    case paused
    case completed
    case discarded
}

enum RunSource: String, Codable {
    case tracked
    case imported
    case manual
    case appleHealth

    var title: String {
        switch self {
        case .tracked: return "iPhone"
        case .imported: return "Import"
        case .manual: return "Manuell"
        case .appleHealth: return "Health / Adidas"
        }
    }
}

@Model
final class Run {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var sourceRaw: String
    var distanceMeters: Double
    var durationSeconds: Double
    var movingDurationSeconds: Double
    var elevationGainMeters: Double
    var calories: Double?
    var averageHeartRate: Double?
    var weatherTempC: Double?
    var weatherSymbol: String?
    var notes: String?
    var analysisTitle: String?
    var analysisBody: String?
    var analysisPending: Bool
    var routeName: String?
    var healthKitUUID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \TrackPoint.run)
    var points: [TrackPoint]

    @Relationship(deleteRule: .cascade, inverse: \Split.run)
    var splits: [Split]

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        status: RunStatus = .active,
        source: RunSource = .tracked
    ) {
        self.id = id
        self.startedAt = startedAt
        self.statusRaw = status.rawValue
        self.sourceRaw = source.rawValue
        self.distanceMeters = 0
        self.durationSeconds = 0
        self.movingDurationSeconds = 0
        self.elevationGainMeters = 0
        self.analysisPending = false
        self.points = []
        self.splits = []
    }

    var status: RunStatus {
        get { RunStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    var source: RunSource {
        get { RunSource(rawValue: sourceRaw) ?? .tracked }
        set { sourceRaw = newValue.rawValue }
    }

    var averagePaceSecondsPerKm: Double? {
        PaceMath.secondsPerKm(distanceMeters: distanceMeters, duration: movingDurationSeconds > 1 ? movingDurationSeconds : durationSeconds)
    }

    var averageSpeedMPS: Double {
        let duration = movingDurationSeconds > 1 ? movingDurationSeconds : durationSeconds
        guard duration > 1 else { return 0 }
        return distanceMeters / duration
    }

    func toDTO() -> RunSummaryDTO {
        RunSummaryDTO(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            duration: durationSeconds,
            averagePaceSecondsPerKm: averagePaceSecondsPerKm,
            averageSpeedMPS: averageSpeedMPS,
            calories: calories,
            averageHeartRate: averageHeartRate,
            elevationGainMeters: elevationGainMeters,
            weatherTempC: weatherTempC,
            weatherSymbol: weatherSymbol,
            source: sourceRaw,
            splits: splits.sorted { $0.kilometerIndex < $1.kilometerIndex }.map {
                SplitDTO(
                    kilometerIndex: $0.kilometerIndex,
                    duration: $0.durationSeconds,
                    paceSecondsPerKm: $0.paceSecondsPerKm,
                    elevationDelta: $0.elevationDelta
                )
            }
        )
    }
}

@Model
final class TrackPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speedMPS: Double
    var accuracy: Double
    var run: Run?

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double, speedMPS: Double, accuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speedMPS = speedMPS
        self.accuracy = accuracy
    }

    var sample: CoordinateSample {
        CoordinateSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            speedMPS: speedMPS,
            accuracy: accuracy
        )
    }
}

@Model
final class Split {
    var kilometerIndex: Int
    var durationSeconds: Double
    var paceSecondsPerKm: Double
    var elevationDelta: Double
    var run: Run?

    init(kilometerIndex: Int, durationSeconds: Double, paceSecondsPerKm: Double, elevationDelta: Double) {
        self.kilometerIndex = kilometerIndex
        self.durationSeconds = durationSeconds
        self.paceSecondsPerKm = paceSecondsPerKm
        self.elevationDelta = elevationDelta
    }
}
