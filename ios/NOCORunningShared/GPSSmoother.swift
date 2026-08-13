import Foundation

public struct RawFix: Sendable, Equatable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double
    public var course: Double
    public var rawSpeed: Double

    public init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        course: Double,
        rawSpeed: Double
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.course = course
        self.rawSpeed = rawSpeed
    }
}

public struct SmoothedFix: Sendable, Equatable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var horizontalAccuracy: Double
    public var speedMPS: Double
    public var isStationary: Bool
    public var accepted: Bool
}

public struct GPSSmoother: Sendable {
    public var maxAccuracyMeters: Double
    public var maxSpeedMPS: Double
    public var stationarySpeedMPS: Double
    public var displayAlpha: Double

    private var lastAccepted: RawFix?
    private var lastGoodSpeed: Double = 0
    private var displayedSpeed: Double = 0
    private var recentSpeeds: [Double] = []
    private var consecutiveRejects: Int = 0

    public init(
        maxAccuracyMeters: Double = 40,
        maxSpeedMPS: Double = 12.5,
        stationarySpeedMPS: Double = 0.45,
        displayAlpha: Double = 0.28
    ) {
        self.maxAccuracyMeters = maxAccuracyMeters
        self.maxSpeedMPS = maxSpeedMPS
        self.stationarySpeedMPS = stationarySpeedMPS
        self.displayAlpha = displayAlpha
    }

    public mutating func reset() {
        lastAccepted = nil
        lastGoodSpeed = 0
        displayedSpeed = 0
        recentSpeeds.removeAll(keepingCapacity: true)
        consecutiveRejects = 0
    }

    public mutating func ingest(_ fix: RawFix) -> SmoothedFix {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxAccuracyMeters else {
            consecutiveRejects += 1
            return rejected(fix)
        }

        guard let previous = lastAccepted else {
            lastAccepted = fix
            let seeded = clampSpeed(max(0, fix.rawSpeed))
            lastGoodSpeed = seeded
            displayedSpeed = seeded
            return SmoothedFix(
                timestamp: fix.timestamp,
                latitude: fix.latitude,
                longitude: fix.longitude,
                altitude: fix.altitude,
                horizontalAccuracy: fix.horizontalAccuracy,
                speedMPS: displayedSpeed,
                isStationary: seeded < stationarySpeedMPS,
                accepted: true
            )
        }

        let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0.2, dt < 30 else {
            consecutiveRejects += 1
            return rejected(fix)
        }

        let gap = haversineMeters(previous, fix)
        let derivedSpeed = gap / dt
        let candidate = median([max(0, fix.rawSpeed), derivedSpeed, lastGoodSpeed])

        if derivedSpeed > maxSpeedMPS, gap > max(previous.horizontalAccuracy, 12) {
            consecutiveRejects += 1
            if consecutiveRejects < 4 {
                return rejected(fix)
            }
        }

        let capped = clampSpeed(candidate)
        let stationary = capped < stationarySpeedMPS || gap < 1.4
        let usableSpeed = stationary ? 0 : capped

        lastAccepted = fix
        lastGoodSpeed = usableSpeed
        consecutiveRejects = 0
        pushSpeed(usableSpeed)
        let blended = median(recentSpeeds + [usableSpeed])
        displayedSpeed += (blended - displayedSpeed) * displayAlpha
        if displayedSpeed < stationarySpeedMPS { displayedSpeed = 0 }

        return SmoothedFix(
            timestamp: fix.timestamp,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude,
            horizontalAccuracy: fix.horizontalAccuracy,
            speedMPS: displayedSpeed,
            isStationary: stationary,
            accepted: true
        )
    }

    private mutating func rejected(_ fix: RawFix) -> SmoothedFix {
        displayedSpeed += (0 - displayedSpeed) * 0.08
        return SmoothedFix(
            timestamp: fix.timestamp,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude,
            horizontalAccuracy: fix.horizontalAccuracy,
            speedMPS: displayedSpeed,
            isStationary: displayedSpeed < stationarySpeedMPS,
            accepted: false
        )
    }

    private func clampSpeed(_ speed: Double) -> Double {
        min(max(0, speed), maxSpeedMPS)
    }

    private mutating func pushSpeed(_ speed: Double) {
        recentSpeeds.append(speed)
        if recentSpeeds.count > 5 {
            recentSpeeds.removeFirst()
        }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private func haversineMeters(_ a: RawFix, _ b: RawFix) -> Double {
        let r = 6_370_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}
