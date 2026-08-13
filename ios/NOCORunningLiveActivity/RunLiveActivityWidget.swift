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
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                        Text(RunFormatters.distanceWithUnit(context.state.distanceMeters, units: .metric))
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(context.state.status == "Pause" ? .orange : .mint)
                        Text(RunFormatters.paceClock(context.state.paceSecondsPerKm ?? 0))
                            .font(.headline.monospacedDigit())
                        Text("min/km")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(RunFormatters.duration(TimeInterval(context.state.elapsedSeconds)), systemImage: "clock")
                            .font(.title3.monospacedDigit())
                        Spacer()
                        Text(context.state.status)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background((context.state.status == "Pause" ? Color.orange : Color.cyan).opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                Text(RunFormatters.distance(context.state.distanceMeters, units: .metric) + " km")
                    .monospacedDigit()
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.cyan)
            }
        }
    }

    private func lockScreen(context: ActivityViewContext<RunActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOCO RUNNING")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.cyan)
                Text(RunFormatters.duration(TimeInterval(context.state.elapsedSeconds)))
                    .font(.largeTitle.monospacedDigit().weight(.semibold))
                Text(context.state.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.status == "Pause" ? .orange : .secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(RunFormatters.distanceWithUnit(context.state.distanceMeters, units: .metric))
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text(RunFormatters.pace(secondsPerKm: context.state.paceSecondsPerKm, units: .metric))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.45))
        .activitySystemActionForegroundColor(.white)
    }
}
