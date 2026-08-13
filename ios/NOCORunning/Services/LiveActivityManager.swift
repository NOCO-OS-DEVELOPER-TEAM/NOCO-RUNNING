import Foundation
import ActivityKit

@MainActor
final class LiveActivityManager {
    private var activity: Activity<RunActivityAttributes>?
    private var lastPush: Date = .distantPast

    func start(startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let attributes = RunActivityAttributes(startedAt: startedAt)
        let state = RunActivityAttributes.ContentState(
            elapsedSeconds: 0,
            distanceMeters: 0,
            paceSecondsPerKm: nil,
            status: "Läuft"
        )
        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        } catch {
            activity = nil
        }
    }

    func update(snapshot: LiveSnapshot) {
        guard let activity else { return }
        guard Date.now.timeIntervalSince(lastPush) >= 1 else { return }
        lastPush = .now
        let status: String = {
            switch snapshot.phase {
            case .paused: return "Pause"
            case .running: return "Läuft"
            default: return snapshot.phase.rawValue
            }
        }()
        let state = RunActivityAttributes.ContentState(
            elapsedSeconds: Int(snapshot.elapsed),
            distanceMeters: snapshot.distanceMeters,
            paceSecondsPerKm: snapshot.averagePaceSecondsPerKm,
            status: status
        )
        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(8)))
        }
    }

    func end() {
        guard let activity else { return }
        let final = activity.content.state
        Task {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}
