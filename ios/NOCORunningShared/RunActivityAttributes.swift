import Foundation
import ActivityKit

public struct RunActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var elapsedSeconds: Int
        public var distanceMeters: Double
        public var paceSecondsPerKm: Double?
        public var status: String

        public init(elapsedSeconds: Int, distanceMeters: Double, paceSecondsPerKm: Double?, status: String) {
            self.elapsedSeconds = elapsedSeconds
            self.distanceMeters = distanceMeters
            self.paceSecondsPerKm = paceSecondsPerKm
            self.status = status
        }
    }

    public var startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }
}
