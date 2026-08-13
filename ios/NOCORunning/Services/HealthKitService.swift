import Foundation
import HealthKit
import CoreLocation

@MainActor
final class HealthKitService: ObservableObject {
    @Published private(set) var isAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var latestHeartRate: Double?
    @Published private(set) var latestSteps: Double?
    @Published private(set) var latestWeightKg: Double?
    @Published private(set) var latestWorkoutDistanceMeters: Double?

    private let store = HKHealthStore()
    private var hrQuery: HKQuery?
    private var workout: HKWorkoutBuilder?
    private let workoutConfig = HKWorkoutConfiguration()

    init() {
        workoutConfig.activityType = .running
        workoutConfig.locationType = .outdoor
    }

    func requestAccess() async {
        guard isAvailable else { return }
        var read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .stepCount,
            .bodyMass,
            .activeEnergyBurned,
            .distanceWalkingRunning
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                read.insert(type)
            }
        }

        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        for identifier in [HKQuantityTypeIdentifier.distanceWalkingRunning, .activeEnergyBurned] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                share.insert(type)
            }
        }

        do {
            try await store.requestAuthorization(toShare: share, read: read)
            isAuthorized = true
            await refreshSnapshot()
        } catch {
            isAuthorized = false
        }
    }

    func runningWorkoutDrafts(limit: Int = 40) async -> [HealthWorkoutDraft] {
        guard isAvailable else { return [] }
        let workouts = await fetchRunningWorkouts(limit: limit)
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.noco.running"
        var drafts: [HealthWorkoutDraft] = []
        for workout in workouts {
            let bundleID = workout.sourceRevision.source.bundleIdentifier
            if bundleID == ownBundle { continue }
            let locations = await routeLocations(for: workout)
            drafts.append(
                HealthWorkoutDraft(
                    uuid: workout.uuid,
                    startedAt: workout.startDate,
                    endedAt: workout.endDate,
                    duration: workout.duration,
                    distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                    calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                    elevationGainMeters: elevation(from: workout, locations: locations),
                    averageHeartRate: await averageHeartRate(for: workout),
                    sourceName: workout.sourceRevision.source.name,
                    bundleID: bundleID,
                    locations: locations
                )
            )
        }
        return drafts
    }

    func refreshSnapshot() async {
        latestHeartRate = await latest(.heartRate)
        latestSteps = await sumToday(.stepCount)
        latestWeightKg = await latest(.bodyMass).map { $0 }
        latestWorkoutDistanceMeters = await sumToday(.distanceWalkingRunning)
    }

    func beginWorkout() {
        guard isAvailable, isAuthorized else { return }
        startHeartRateQuery()
    }

    func endWorkout() {
        if let hrQuery {
            store.stop(hrQuery)
        }
        hrQuery = nil
    }

    func saveCompletedRun(_ run: Run) async {
        guard isAvailable, isAuthorized, run.status == .completed else { return }
        let start = run.startedAt
        let end = run.endedAt ?? start.addingTimeInterval(run.durationSeconds)
        let workout = HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            duration: run.durationSeconds,
            totalEnergyBurned: run.calories.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
            totalDistance: HKQuantity(unit: .meter(), doubleValue: run.distanceMeters),
            metadata: [
                HKMetadataKeyIndoorWorkout: false
            ]
        )
        do {
            try await store.save(workout)
        } catch {
            // Health write is optional; the local run remains the source of truth.
        }
    }

    private func startHeartRateQuery() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            let bpm = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            Task { @MainActor in
                self?.latestHeartRate = bpm
            }
        }
        hrQuery = query
        store.execute(query)

        let anchored = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            let bpm = (samples?.last as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            Task { @MainActor in
                self?.latestHeartRate = bpm
            }
        }
        anchored.updateHandler = { [weak self] _, samples, _, _, _ in
            let bpm = (samples?.last as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            Task { @MainActor in
                self?.latestHeartRate = bpm
            }
        }
        store.execute(anchored)
        hrQuery = anchored
    }

    private func latest(_ id: HKQuantityTypeIdentifier) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let unit: HKUnit = {
            switch id {
            case .heartRate: return HKUnit.count().unitDivided(by: .minute())
            case .bodyMass: return .gramUnit(with: .kilo)
            default: return .count()
            }
        }()
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchRunningWorkouts(limit: Int) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForWorkouts(with: .running)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private func routeLocations(for workout: HKWorkout) async -> [CLLocation] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        var points: [CLLocation] = []
        for route in routes {
            points.append(contentsOf: await locations(in: route))
        }
        return points.sorted { $0.timestamp < $1.timestamp }
    }

    private func locations(in route: HKWorkoutRoute) async -> [CLLocation] {
        await withCheckedContinuation { continuation in
            let box = RouteAccumulator()
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let locations {
                    box.locations.append(contentsOf: locations)
                }
                guard done || error != nil, !box.finished else { return }
                box.finished = true
                continuation.resume(returning: box.locations)
            }
            store.execute(query)
        }
    }

    private func averageHeartRate(for workout: HKWorkout) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func elevation(from workout: HKWorkout, locations: [CLLocation]) -> Double {
        if let quantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            return quantity.doubleValue(for: .meter())
        }
        var gain = 0.0
        for pair in zip(locations, locations.dropFirst()) {
            let delta = pair.1.altitude - pair.0.altitude
            if delta > 0, delta < 8 { gain += delta }
        }
        return gain
    }
}

private final class RouteAccumulator {
    var finished = false
    var locations: [CLLocation] = []
}

struct HealthWorkoutDraft {
    var uuid: UUID
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var distanceMeters: Double
    var calories: Double?
    var elevationGainMeters: Double
    var averageHeartRate: Double?
    var sourceName: String
    var bundleID: String
    var locations: [CLLocation]
}
