import Foundation
import ActivityKit

/// Live Activity : le cours en cours (ou celui qui commence dans moins d'une heure) reste affiché
/// sur l'écran verrouillé et dans la Dynamic Island, avec le temps restant qui défile tout seul.
@MainActor
enum LiveActivityManager {
    static func update(courses: [Course], enabled: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let pair = currentAndNext(courses, at: now)
        var target: Course? = pair.current
        if target == nil, let next = pair.next, next.start.timeIntervalSince(now) <= 3600 { target = next }

        let existing = Activity<CourseActivityAttributes>.activities

        guard enabled, let course = target else {
            for activity in existing { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }

        let state = CourseActivityAttributes.ContentState(
            title: course.title,
            location: course.displayLocation,
            start: course.start,
            end: course.end,
            ongoing: course.isOngoing(at: now),
            colorHex: course.colorHex,
            isExam: course.isExam
        )
        let content = ActivityContent(state: state, staleDate: course.end)

        // Même cours déjà affiché : simple mise à jour
        if let same = existing.first(where: { $0.content.state.title == course.title && $0.content.state.start == course.start }) {
            Task { await same.update(content) }
            for other in existing where other.id != same.id { Task { await other.end(nil, dismissalPolicy: .immediate) } }
            return
        }

        for activity in existing { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        do {
            let activity = try Activity.request(
                attributes: CourseActivityAttributes(calendarName: course.calendarName),
                content: content,
                pushType: nil
            )
            // Disparaît toute seule à la fin du cours
            Task {
                let delay = max(0, course.end.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        } catch {
            print("Live Activity impossible : \(error)")
        }
    }
}
