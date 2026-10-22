#if os(iOS)
import WidgetKit
import SwiftUI
import ActivityKit

/// Live Activity : écran verrouillé + Dynamic Island, avec le temps restant qui défile tout seul.
struct CourseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            LockScreenCourseView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.65))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let color = s.isExam ? Color.examRed : Color(hex: s.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: s.isExam ? "pencil.and.list.clipboard" : "calendar")
                        .font(.title2)
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: s)
                        .font(.title3.bold())
                        .monospacedDigit()
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(["\(Fmt.time(s.start)) – \(Fmt.time(s.end))", s.location.isEmpty ? "" : "📍 \(s.location)"]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if s.ongoing {
                            ProgressView(timerInterval: s.start...s.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(color)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "calendar").foregroundStyle(color)
            } compactTrailing: {
                CountdownText(state: s)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "calendar").foregroundStyle(color)
            }
            .keylineTint(color)
        }
    }
}

/// « reste 23:12 » pendant le cours, « 14:59 » avant.
struct CountdownText: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        if state.ongoing {
            Text(timerInterval: state.start...state.end, countsDown: true)
        } else {
            Text(state.start, style: .timer)
        }
    }
}

struct LockScreenCourseView: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        let color = state.isExam ? Color.examRed : Color(hex: state.colorHex)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.ongoing ? "🔴 EN COURS" : (state.isExam ? "📝 EXAMEN" : "⏳ BIENTÔT"))
                    .font(.caption.bold())
                    .foregroundStyle(state.ongoing ? Color.red : Color.accentViolet)
                Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text(["\(Fmt.time(state.start)) – \(Fmt.time(state.end))", state.location.isEmpty ? "" : "📍 \(state.location)"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                if state.ongoing {
                    ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(color)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text(state.ongoing ? "reste" : "dans").font(.caption2).foregroundStyle(.white.opacity(0.7))
                CountdownText(state: state)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100, alignment: .trailing)
            }
        }
        .padding(14)
    }
}
#endif
