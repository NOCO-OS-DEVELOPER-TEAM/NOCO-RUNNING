import SwiftUI
import WidgetKit

@main
struct NOCORunningLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivityWidget()
    }
}

struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            lockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOCO")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(RunFormatters.distanceWithUnit(context.state.distanceMeters, units: .metric))
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.status)
                            .font(.caption2)
                        Text(RunFormatters.pace(secondsPerKm: context.state.paceSecondsPerKm, units: .metric))
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(RunFormatters.duration(TimeInterval(context.state.elapsedSeconds)))
                            .font(.title3.monospacedDigit())
                        Spacer()
                        Image(systemName: "figure.run")
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text(RunFormatters.distance(context.state.distanceMeters, units: .metric))
                    .monospacedDigit()
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }

    private func lockScreen(context: ActivityViewContext<RunActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOCO RUNNING")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(RunFormatters.duration(TimeInterval(context.state.elapsedSeconds)))
                    .font(.title.monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(RunFormatters.distanceWithUnit(context.state.distanceMeters, units: .metric))
                    .font(.headline.monospacedDigit())
                Text(RunFormatters.pace(secondsPerKm: context.state.paceSecondsPerKm, units: .metric))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.35))
        .activitySystemActionForegroundColor(.white)
    }
}
