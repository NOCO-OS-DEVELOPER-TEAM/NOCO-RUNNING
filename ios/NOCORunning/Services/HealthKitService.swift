import Foundation
import HealthKit
import CoreLocation
import UIKit

@MainActor
final class HealthKitService: ObservableObject {
    @Published private(set) var isAvailable: Bool = HKHealthStore.isHealthDataAvailable()
    /// Write permission for workouts (readable). Read grants are private — we probe separately.
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var authorizationState: HealthAuthState = .unknown
    @Published private(set) var lastError: String?
    @Published private(set) var latestHeartRate: Double?
    @Published private(set) var latestSteps: Double?
    @Published private(set) var latestWeightKg: Double?
    @Published private(set) var latestWorkoutDistanceMeters: Double?
    @Published private(set) var lastWorkoutProbeCount: Int = 0

    private let store = HKHealthStore()
    private var hrQuery: HKQuery?
    private let workoutConfig = HKWorkoutConfiguration()

    /// Known Adidas / Runtastic / Watch companion bundle fragments.
    private let externalRunBundleHints = [
        "adidas", "runtastic", "com.apple.health", "workout"
    ]

    init() {
        workoutConfig.activityType = .running
        workoutConfig.locationType = .outdoor
        refreshLocalAuthFlags()
    }

    private var readTypes: Set<HKObjectType> {
        var read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .stepCount,
            .bodyMass,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .runningSpeed,
            .vo2Max
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                read.insert(type)
            }
        }
        return read
    }

    private var shareTypes: Set<HKSampleType> {
        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        for identifier in [
            HKQuantityTypeIdentifier.distanceWalkingRunning,
            .activeEnergyBurned,
            .heartRate
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                share.insert(type)
            }
        }
        return share
    }

    /// Call from a visible UI action (button) so the system sheet can appear.
    @discardableResult
    func requestAccess() async -> Bool {
        guard isAvailable else {
            lastError = "HealthKit ist auf diesem Gerät nicht verfügbar."
            authorizationState = .unavailable
            isAuthorized = false
            return false
        }

        lastError = nil
        do {
            // Ask the system whether a prompt is still needed (helps diagnostics).
            let requestStatus = try await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
            if requestStatus == .shouldRequest {
                authorizationState = .needsRequest
            }

            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            refreshLocalAuthFlags()
            await refreshSnapshot()
            let probe = await fetchRunningWorkouts(limit: 5)
            lastWorkoutProbeCount = probe.count

            // Read access is opaque; treat successful request + no throw as "connected".
            // If write is denied, still allow reads when the user enabled them in Health.
            if authorizationState == .denied {
                lastError = "Schreiben in Health ist aus. Bitte in der Health-App unter Teilen → Apps → NOCO RUNNING die Kategorien aktivieren."
                return false
            }
            authorizationState = .connected
            isAuthorized = true
            lastError = nil
            return true
        } catch {
            let message = error.localizedDescription
            // Missing entitlement / sideload without HealthKit typically lands here with no sheet.
            if message.localizedCaseInsensitiveContains("authorization")
                || message.localizedCaseInsensitiveContains("entitlement")
                || (error as NSError).domain == "com.apple.healthkit" {
                lastError = "Health-Berechtigung fehlgeschlagen (\(message)). App neu installieren (IPA mit HealthKit-Entitlement) und unter Einstellungen → Health → Datenzugriff NOCO erlauben."
            } else {
                lastError = message
            }
            authorizationState = .failed
            isAuthorized = false
            return false
        }
    }

    func openSystemHealthSettings() {
        // Health app data-access screen (best effort) → app settings fallback.
        let candidates = [
            URL(string: "x-apple-health://"),
            URL(string: UIApplication.openSettingsURLString)
        ].compactMap { $0 }
        for url in candidates where UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
    }

    func runningWorkoutDrafts(limit: Int = 400) async -> [HealthWorkoutDraft] {
        guard isAvailable else { return [] }
        if !isAuthorized {
            _ = await requestAccess()
        }
        let workouts = await fetchImportableWorkouts(limit: limit)
        lastWorkoutProbeCount = workouts.count
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.noco.running"
        var drafts: [HealthWorkoutDraft] = []
        for workout in workouts {
            let bundleID = workout.sourceRevision.source.bundleIdentifier
            if bundleID == ownBundle { continue }
            let locations = await routeLocations(for: workout)
            let hr = await averageHeartRate(for: workout)
            drafts.append(
                HealthWorkoutDraft(
                    uuid: workout.uuid,
                    startedAt: workout.startDate,
                    endedAt: workout.endDate,
                    duration: workout.duration,
                    distanceMeters: distanceMeters(for: workout),
                    calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                    elevationGainMeters: elevation(from: workout, locations: locations),
                    averageHeartRate: hr,
                    sourceName: workout.sourceRevision.source.name,
                    bundleID: bundleID,
                    locations: locations
                )
            )
        }
        return drafts
    }

    func refreshSnapshot() async {
        refreshLocalAuthFlags()
        latestHeartRate = await latest(.heartRate)
        latestSteps = await sumToday(.stepCount)
        latestWeightKg = await latest(.bodyMass)
        latestWorkoutDistanceMeters = await sumToday(.distanceWalkingRunning)
    }

    func beginWorkout() {
        guard isAvailable else { return }
        if !isAuthorized {
            Task { _ = await requestAccess() }
        }
        startHeartRateQuery()
    }

    func endWorkout() {
        if let hrQuery {
            store.stop(hrQuery)
        }
        hrQuery = nil
    }

    func saveCompletedRun(_ run: Run) async {
        guard isAvailable, run.status == .completed else { return }
        if !isAuthorized {
            _ = await requestAccess()
        }
        guard isAuthorized else { return }
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
            lastError = "Lauf konnte nicht in Health gespeichert werden: \(error.localizedDescription)"
        }
    }

    private func refreshLocalAuthFlags() {
        guard isAvailable else {
            authorizationState = .unavailable
            isAuthorized = false
            return
        }
        let writeStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        switch writeStatus {
        case .sharingAuthorized:
            authorizationState = .connected
            isAuthorized = true
        case .sharingDenied:
            // User may still have granted read-only — keep trying reads.
            authorizationState = .denied
            isAuthorized = true
        case .notDetermined:
            authorizationState = .needsRequest
            isAuthorized = false
        @unknown default:
            authorizationState = .unknown
        }
    }

    private func startHeartRateQuery() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        if let hrQuery {
            store.stop(hrQuery)
        }

        let anchored = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            let bpm = (samples?.last as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            Task { @MainActor in
                if let bpm { self?.latestHeartRate = bpm }
            }
        }
        anchored.updateHandler = { [weak self] _, samples, _, _, _ in
            let bpm = (samples?.last as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            Task { @MainActor in
                if let bpm { self?.latestHeartRate = bpm }
            }
        }
        store.execute(anchored)
        hrQuery = anchored
    }

    private func latest(_ id: HKQuantityTypeIdentifier) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let unit: HKUnit = {
            switch id {
            case .heartRate, .restingHeartRate: return HKUnit.count().unitDivided(by: .minute())
            case .bodyMass: return .gramUnit(with: .kilo)
            case .distanceWalkingRunning: return .meter()
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

    private func fetchImportableWorkouts(limit: Int) async -> [HKWorkout] {
        let running = await fetchWorkouts(activity: .running, limit: limit)
        // Some Adidas exports land as traditional training / other — pull extras by source name.
        let extras = await fetchWorkouts(activity: nil, limit: min(limit, 200))
        var merged: [UUID: HKWorkout] = [:]
        for workout in running {
            merged[workout.uuid] = workout
        }
        for workout in extras {
            let name = workout.sourceRevision.source.name.lowercased()
            let bundle = workout.sourceRevision.source.bundleIdentifier.lowercased()
            let looksExternalRun = externalRunBundleHints.contains { bundle.contains($0) || name.contains($0) }
                || name.contains("adidas")
                || bundle.contains("adidas")
                || bundle.contains("runtastic")
            let isRunLike = workout.workoutActivityType == .running
                || workout.workoutActivityType == .walking
                || (looksExternalRun && (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) >= 200)
            if isRunLike {
                merged[workout.uuid] = workout
            }
        }
        return Array(merged.values)
            .sorted { $0.endDate > $1.endDate }
            .prefix(limit)
            .map { $0 }
    }

    private func fetchRunningWorkouts(limit: Int) async -> [HKWorkout] {
        await fetchWorkouts(activity: .running, limit: limit)
    }

    private func fetchWorkouts(activity: HKWorkoutActivityType?, limit: Int) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let predicate: NSPredicate? = activity.map { HKQuery.predicateForWorkouts(with: $0) }
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

    private func distanceMeters(for workout: HKWorkout) -> Double {
        if let meters = workout.totalDistance?.doubleValue(for: .meter()), meters > 0 {
            return meters
        }
        if let quantity = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter()), quantity > 0 {
            return quantity
        }
        return 0
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
        let unit = HKUnit.count().unitDivided(by: .minute())
        // Metadata key as string — the HKMetadataKeyAverageHeartRate symbol is not always visible to Swift.
        if let meta = workout.metadata?["HKAverageHeartRate"] as? HKQuantity {
            return meta.doubleValue(for: unit)
        }
        if let number = workout.metadata?["HKAverageHeartRate"] as? NSNumber {
            return number.doubleValue
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let statistical = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
        if let statistical { return statistical }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map { $0.quantity.doubleValue(for: unit) } ?? []
                guard !values.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: values.reduce(0, +) / Double(values.count))
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

enum HealthAuthState: Equatable {
    case unknown
    case unavailable
    case needsRequest
    case connected
    case denied
    case failed

    var label: String {
        switch self {
        case .unknown: return "Unbekannt"
        case .unavailable: return "Nicht verfügbar"
        case .needsRequest: return "Berechtigung nötig"
        case .connected: return "Verbunden"
        case .denied: return "Eingeschränkt / prüfen"
        case .failed: return "Fehler"
        }
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
