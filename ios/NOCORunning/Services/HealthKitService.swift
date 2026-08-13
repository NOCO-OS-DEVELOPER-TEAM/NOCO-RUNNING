import Foundation
import HealthKit

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
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .bodyMass),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKObjectType.workoutType()
        ].compactMap { $0 }

        let share: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.workoutType()
        ].compactMap { $0 }

        do {
            try await store.requestAuthorization(toShare: share, read: read)
            isAuthorized = true
            await refreshSnapshot()
        } catch {
            isAuthorized = false
        }
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

    private func sumToday(_ id: HKQuantityTypeIdentifier) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let unit: HKUnit = id == .distanceWalkingRunning ? .meter() : .count()
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}
