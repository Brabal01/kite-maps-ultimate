import ActivityKit
import SwiftUI
import WidgetKit

/** Kite's only widget: the next turn on the lock screen and in the Dynamic Island while driving. */
@main
struct KiteWidgets: WidgetBundle {
    var body: some Widget {
        NavLiveActivity()
    }
}

private let teal = Color(red: 0.08, green: 0.72, blue: 0.65)

struct NavLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavActivityAttributes.self) { context in
            LockScreenTurn(state: context.state, destination: context.attributes.destination)
                .activityBackgroundTint(Color(red: 0.06, green: 0.09, blue: 0.16))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: s.symbol)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(teal)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.arrived ? "" : s.distance)
                        .font(.system(size: 26, weight: .heavy))
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.instruction).font(.system(size: 20, weight: .bold)).lineLimit(1)
                        Text([s.road, "Arrive \(s.arrival)"].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: s.symbol).font(.system(size: 16, weight: .bold)).foregroundColor(teal)
            } compactTrailing: {
                Text(s.arrived ? "Here" : s.distance).font(.system(size: 15, weight: .bold)).monospacedDigit()
            } minimal: {
                Image(systemName: s.symbol).font(.system(size: 15, weight: .bold)).foregroundColor(teal)
            }
        }
    }
}

/** Big arrow, distance and turn, then the road and when you'll arrive: readable at a glance in a holder. */
struct LockScreenTurn: View {
    let state: NavActivityAttributes.ContentState
    let destination: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.symbol)
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(teal))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !state.arrived {
                        Text(state.distance).font(.system(size: 26, weight: .heavy)).monospacedDigit()
                    }
                    Text(state.instruction).font(.system(size: 20, weight: .bold)).lineLimit(1)
                }
                Text([state.road, state.arrived ? destination : "Arrive \(state.arrival)"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
