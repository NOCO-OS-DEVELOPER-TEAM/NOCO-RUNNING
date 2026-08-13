import Foundation
import Combine
import SwiftData
import CoreLocation

@MainActor
final class RunTracker: ObservableObject {
    @Published private(set) var snapshot: LiveSnapshot = .empty
    @Published private(set) var path: [CLLocationCoordinate2D] = []
    @Published private(set) var activeRunID: UUID?
    @Published var lastError: String?

    private let location = LocationEngine()
    private var smoother = GPSSmoother()
    private var clock: Timer?
    private var lastFlush: Date = .now
    private var pendingPoints: [CoordinateSample] = []
    private var lastAltitude: Double?
    private var splitCursorMeters: Double = 0
    private var splitCursorTime: TimeInterval = 0
    private var splitCursorElevation: Double = 0
    private var pauseStartedAt: Date?
    private var accumulatedPause: TimeInterval = 0
    private var lastUIPush: Date = .distantPast
    private var context: ModelContext?
    private var weightKg: Double?
    private var health: HealthKitService?
    private var liveActivity: LiveActivityManager?

    init() {
        location.onFix = { [weak self] fix in
            Task { @MainActor in
                self?.consume(fix)
            }
        }
        location.onError = { [weak self] error in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
            }
        }
    }

    func configure(context: ModelContext, health: HealthKitService, liveActivity: LiveActivityManager, weightKg: Double?) {
        self.context = context
        self.health = health
        self.liveActivity = liveActivity
        self.weightKg = weightKg
    }

    func prepareGPS() {
        location.prepare()
        var next = snapshot
        next.phase = snapshot.phase == .idle ? .preparing : snapshot.phase
        next.gpsReady = location.isReady
        next.gpsAccuracy = location.accuracy
        if let last = location.lastFix {
            next.latitude = last.coordinate.latitude
            next.longitude = last.coordinate.longitude
        }
        snapshot = next
    }

    func start(routeName: String? = nil) {
        guard snapshot.phase == .idle || snapshot.phase == .preparing else { return }
        smoother.reset()
        path = []
        pendingPoints = []
        lastAltitude = nil
        splitCursorMeters = 0
        splitCursorTime = 0
        splitCursorElevation = 0
        accumulatedPause = 0
        pauseStartedAt = nil

        let run = Run(startedAt: .now, status: .active, source: .tracked)
        run.routeName = routeName
        context?.insert(run)
        try? context?.save()
        activeRunID = run.id

        location.startTracking()
        liveActivity?.start(startedAt: run.startedAt)
        startClock()
        health?.beginWorkout()

        var next = LiveSnapshot.empty
        next.phase = .running
        next.startedAt = run.startedAt
        next.gpsReady = location.isReady
        snapshot = next
        Haptics.start()
    }

    func pause() {
        guard snapshot.phase == .running else { return }
        pauseStartedAt = .now
        flush(force: true)
        updateActive { $0.status = .paused }
        liveActivity?.update(snapshot: pausedSnapshot())
        var next = snapshot
        next.phase = .paused
        snapshot = next
        Haptics.pause()
    }

    func resume() {
        guard snapshot.phase == .paused else { return }
        if let pauseStartedAt {
            accumulatedPause += Date.now.timeIntervalSince(pauseStartedAt)
        }
        pauseStartedAt = nil
        updateActive { $0.status = .active }
        var next = snapshot
        next.phase = .running
        snapshot = next
        Haptics.medium()
    }

    func discardActive() {
        clock?.invalidate()
        location.stop()
        liveActivity?.end()
        health?.endWorkout()
        if let run = activeRun() {
            run.status = .discarded
            try? context?.save()
        }
        resetMemory()
    }

    func finish() -> Run? {
        guard snapshot.phase == .running || snapshot.phase == .paused else { return nil }
        if snapshot.phase == .paused, let pauseStartedAt {
            accumulatedPause += Date.now.timeIntervalSince(pauseStartedAt)
        }
        var next = snapshot
        next.phase = .finishing
        snapshot = next
        flush(force: true)

        guard let run = activeRun() else {
            resetMemory()
            return nil
        }

        let elapsed = wallElapsed()
        run.endedAt = .now
        run.status = .completed
        run.durationSeconds = elapsed
        run.movingDurationSeconds = max(0, elapsed - accumulatedPause)
        run.calories = CalorieEstimator.kcal(
            distanceMeters: run.distanceMeters,
            duration: run.movingDurationSeconds,
            weightKg: weightKg
        )
        run.analysisPending = true
        try? context?.save()

        clock?.invalidate()
        location.stop()
        liveActivity?.end()
        health?.endWorkout()
        Haptics.record()

        let finished = run
        resetMemory()
        return finished
    }

    func restoreIfNeeded() {
        guard let context else { return }
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.statusRaw == "active" || $0.statusRaw == "paused" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let run = try? context.fetch(descriptor).first else { return }
        activeRunID = run.id
        path = run.points.sorted { $0.timestamp < $1.timestamp }.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        splitCursorMeters = run.distanceMeters
        location.startTracking()
        startClock()
        var next = snapshot
        next.phase = run.status == .paused ? .paused : .running
        next.startedAt = run.startedAt
        next.distanceMeters = run.distanceMeters
        next.elevationGainMeters = run.elevationGainMeters
        snapshot = next
        liveActivity?.start(startedAt: run.startedAt)
    }

    private func consume(_ fix: RawFix) {
        var next = snapshot
        next.gpsAccuracy = fix.horizontalAccuracy
        next.gpsReady = fix.horizontalAccuracy > 0 && fix.horizontalAccuracy <= 35
        next.latitude = fix.latitude
        next.longitude = fix.longitude

        guard next.phase == .running else {
            snapshot = next
            return
        }

        let smoothed = smoother.ingest(fix)
        next.currentSpeedMPS = smoothed.speedMPS
        next.isStationary = smoothed.isStationary
        next.currentPaceSecondsPerKm = smoothed.speedMPS > 0.45 ? 1000 / smoothed.speedMPS : nil

        if smoothed.accepted {
            if let last = path.last {
                let delta = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: smoothed.latitude, longitude: smoothed.longitude))
                if delta < 80 {
                    next.distanceMeters += delta
                }
            }
            path.append(CLLocationCoordinate2D(latitude: smoothed.latitude, longitude: smoothed.longitude))
            if path.count > 20_000 {
                path.removeFirst(path.count - 20_000)
            }

            if let lastAltitude, smoothed.altitude > lastAltitude {
                let gain = smoothed.altitude - lastAltitude
                if gain < 8 { next.elevationGainMeters += gain }
            }
            lastAltitude = smoothed.altitude

            pendingPoints.append(
                CoordinateSample(
                    timestamp: smoothed.timestamp,
                    latitude: smoothed.latitude,
                    longitude: smoothed.longitude,
                    altitude: smoothed.altitude,
                    speedMPS: smoothed.speedMPS,
                    accuracy: smoothed.horizontalAccuracy
                )
            )
            maybeCloseSplit(distance: next.distanceMeters, elapsed: wallElapsed(), elevation: next.elevationGainMeters)
        }

        next.elapsed = wallElapsed()
        next.movingElapsed = max(0, next.elapsed - accumulatedPause)
        next.averageSpeedMPS = next.movingElapsed > 1 ? next.distanceMeters / next.movingElapsed : 0
        next.averagePaceSecondsPerKm = PaceMath.secondsPerKm(distanceMeters: next.distanceMeters, duration: next.movingElapsed)
        next.calories = CalorieEstimator.kcal(distanceMeters: next.distanceMeters, duration: next.movingElapsed, weightKg: weightKg)
        next.heartRate = health?.latestHeartRate
        next.steps = health?.latestSteps
        snapshot = next

        if Date.now.timeIntervalSince(lastUIPush) > 1 {
            lastUIPush = .now
            liveActivity?.update(snapshot: next)
        }
        if Date.now.timeIntervalSince(lastFlush) > 8 {
            flush(force: false)
        }
    }

    private func startClock() {
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let clock {
            RunLoop.main.add(clock, forMode: .common)
        }
    }

    private func tick() {
        guard snapshot.phase == .running || snapshot.phase == .paused else { return }
        var next = snapshot
        next.elapsed = wallElapsed()
        if snapshot.phase == .running {
            next.movingElapsed = max(0, next.elapsed - accumulatedPause)
        }
        snapshot = next
    }

    private func wallElapsed() -> TimeInterval {
        guard let started = snapshot.startedAt else { return 0 }
        return Date.now.timeIntervalSince(started)
    }

    private func maybeCloseSplit(distance: Double, elapsed: TimeInterval, elevation: Double) {
        let km = Int(distance / 1000)
        let previousKm = Int(splitCursorMeters / 1000)
        guard km > previousKm, km > 0 else { return }
        let duration = elapsed - splitCursorTime
        let elevationDelta = elevation - splitCursorElevation
        let split = Split(
            kilometerIndex: km,
            durationSeconds: duration,
            paceSecondsPerKm: duration,
            elevationDelta: elevationDelta
        )
        activeRun()?.splits.append(split)
        splitCursorMeters = distance
        splitCursorTime = elapsed
        splitCursorElevation = elevation
    }

    private func flush(force: Bool) {
        guard let run = activeRun(), !pendingPoints.isEmpty else { return }
        if !force, pendingPoints.count < 4 { return }
        for sample in pendingPoints {
            let point = TrackPoint(
                timestamp: sample.timestamp,
                latitude: sample.latitude,
                longitude: sample.longitude,
                altitude: sample.altitude,
                speedMPS: sample.speedMPS,
                accuracy: sample.accuracy
            )
            point.run = run
            run.points.append(point)
        }
        pendingPoints.removeAll(keepingCapacity: true)
        run.distanceMeters = snapshot.distanceMeters
        run.durationSeconds = snapshot.elapsed
        run.movingDurationSeconds = snapshot.movingElapsed
        run.elevationGainMeters = snapshot.elevationGainMeters
        try? context?.save()
        lastFlush = .now
    }

    private func activeRun() -> Run? {
        guard let context, let activeRunID else { return nil }
        let id = activeRunID
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func updateActive(_ mutate: (Run) -> Void) {
        guard let run = activeRun() else { return }
        mutate(run)
        try? context?.save()
    }

    private func pausedSnapshot() -> LiveSnapshot {
        var next = snapshot
        next.phase = .paused
        return next
    }

    private func resetMemory() {
        clock?.invalidate()
        clock = nil
        smoother.reset()
        path = []
        pendingPoints = []
        activeRunID = nil
        snapshot = .empty
    }
}
