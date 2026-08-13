import Testing
@testable import NOCORunning

struct GPSSmootherTests {
    @Test func firstAccurateFixIsAccepted() {
        var smoother = GPSSmoother()
        let result = smoother.ingest(fix(accuracy: 8, speed: 3.1))
        #expect(result.accepted)
        #expect(result.speedMPS > 0)
    }

    @Test func inaccurateFixIsRejected() {
        var smoother = GPSSmoother()
        _ = smoother.ingest(fix(accuracy: 8, speed: 3))
        let bad = smoother.ingest(fix(accuracy: 180, speed: 40, secondsLater: 2, latOffset: 0.002))
        #expect(!bad.accepted)
    }

    @Test func standingStillDoesNotInventSpeed() {
        var smoother = GPSSmoother()
        _ = smoother.ingest(fix(accuracy: 6, speed: 0.1))
        let still = smoother.ingest(fix(accuracy: 6, speed: 0.2, secondsLater: 2, latOffset: 0.000001))
        #expect(still.accepted)
        #expect(still.speedMPS < 0.6)
        #expect(still.isStationary)
    }

    @Test func impossibleJumpIsFiltered() {
        var smoother = GPSSmoother()
        _ = smoother.ingest(fix(accuracy: 5, speed: 3.2))
        let jump = smoother.ingest(fix(accuracy: 12, speed: 55, secondsLater: 1, latOffset: 0.02))
        #expect(!jump.accepted)
    }
}

struct LocalImporterTests {
    @Test func parsesGermanRunSentence() {
        let draft = LocalRunImporter.parse("5 km, 32 Minuten, Pace 6:24")
        #expect(draft.distanceMeters != nil)
        #expect(abs((draft.distanceMeters ?? 0) - 5000) < 1)
        #expect(draft.duration != nil)
        #expect(abs((draft.duration ?? 0) - 1920) < 1)
        #expect(draft.averagePaceSecondsPerKm != nil)
        #expect(abs((draft.averagePaceSecondsPerKm ?? 0) - 384) < 1)
        #expect(draft.confidence > 0.6)
    }

    @Test func computesPaceWhenOnlyDistanceAndTimeExist() {
        let draft = LocalRunImporter.parse("10 kilometer in 55:00")
        #expect(abs((draft.distanceMeters ?? 0) - 10000) < 1)
        #expect(draft.averagePaceSecondsPerKm != nil)
    }
}

struct PaceMathTests {
    @Test func secondsPerKmFromDistanceAndTime() {
        let pace = PaceMath.secondsPerKm(distanceMeters: 5000, duration: 1800)
        #expect(pace != nil)
        #expect(abs((pace ?? 0) - 360) < 0.01)
    }
}

private func fix(
    accuracy: Double,
    speed: Double,
    secondsLater: TimeInterval = 0,
    latOffset: Double = 0
) -> RawFix {
    RawFix(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000 + secondsLater),
        latitude: 48.4 + latOffset,
        longitude: 10.0,
        altitude: 480,
        horizontalAccuracy: accuracy,
        verticalAccuracy: 4,
        course: 12,
        rawSpeed: speed
    )
}
