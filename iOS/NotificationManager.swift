import Foundation
import UserNotifications

/// Notifications locales : rappel avant chaque cours, examen la veille à 19 h, changements d'emploi du temps.
enum NotificationManager {
    private static let center = UNUserNotificationCenter.current()
    private static let reminderPrefix = "reminder-"
    private static let examPrefix = "exam-"

    static func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Reprogramme les rappels (iOS limite à 64 notifications en attente : on garde les plus proches).
    static func reschedule(courses: [Course], remindersOn: Bool, reminderMinutes: Int, examOn: Bool) {
        let now = Date()
        let horizon = now.addingTimeInterval(8 * 86400)
        let upcoming = courses.filter { !$0.isHoliday && $0.start > now && $0.start < horizon }

        var requests: [UNNotificationRequest] = []

        if remindersOn {
            for c in upcoming {
                let fire = c.start.addingTimeInterval(-Double(reminderMinutes) * 60)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "⏳ Bientôt : \(c.title)"
                content.body = [c.displayLocation.isEmpty ? nil : "📍 \(c.displayLocation)", "à \(Fmt.time(c.start)) (dans \(reminderMinutes) min)"]
                    .compactMap { $0 }.joined(separator: " · ")
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                content.threadIdentifier = "reminders"
                requests.append(UNNotificationRequest(
                    identifier: reminderPrefix + c.id,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)))
            }
        }

        if examOn {
            for c in upcoming where c.isExam {
                let cal = Calendar.current
                guard let eve = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: c.start)),
                      let fire = cal.date(bySettingHour: 19, minute: 0, second: 0, of: eve) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "📝 Examen demain : \(c.title)"
                content.body = "à \(Fmt.time(c.start))" + (c.displayLocation.isEmpty ? "" : " · 📍 \(c.displayLocation)")
                content.sound = .default
                content.threadIdentifier = "exams"
                // Si 19 h la veille est déjà passé, on prévient dans une minute
                let delay = max(60, fire.timeIntervalSince(now))
                requests.append(UNNotificationRequest(
                    identifier: examPrefix + c.id,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
            }
        }

        let sorted = requests.sorted { a, b in
            ((a.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 0) < ((b.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 0)
        }.prefix(60)

        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) || $0.hasPrefix(examPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for r in sorted { center.add(r) }
        }
    }

    /// Notification « changements dans ton emploi du temps » après une synchro.
    static func notifyChanges(_ changes: [ScheduleChange], hidden: Set<String>) {
        guard UserDefaults.standard.object(forKey: "changeNotifOn") as? Bool ?? true else { return }
        var seen = Set<String>()
        let relevant = changes.filter { c in
            !hidden.contains(c.title) && seen.insert("\(c.type)|\(c.title)|\(c.oldStart?.timeIntervalSince1970 ?? 0)|\(c.newStart?.timeIntervalSince1970 ?? 0)").inserted
        }
        guard !relevant.isEmpty else { return }

        func describe(_ c: ScheduleChange) -> String {
            func d(_ date: Date?) -> String { date.map { "\(Fmt.dayShort($0)) \(Fmt.time($0))" } ?? "?" }
            switch c.type {
            case .added: return "🆕 \(c.title) · \(d(c.newStart))"
            case .removed: return "❌ \(c.title) annulé · \(d(c.oldStart))"
            case .modified:
                var s = "✏️ \(c.title)"
                if c.oldStart != c.newStart { s += " · \(d(c.oldStart)) → \(d(c.newStart))" }
                if c.oldLocation != c.newLocation { s += " · salle \(c.newLocation ?? "?")" }
                return s
            }
        }

        let content = UNMutableNotificationContent()
        content.title = relevant.count == 1 ? "📅 Changement dans ton emploi du temps" : "📅 \(relevant.count) changements dans ton emploi du temps"
        content.body = relevant.prefix(6).map(describe).joined(separator: "\n") + (relevant.count > 6 ? "\n+ \(relevant.count - 6) autres" : "")
        content.sound = .default
        content.userInfo = ["openChanges": true]
        center.add(UNNotificationRequest(identifier: "changes-\(UUID().uuidString)", content: content, trigger: nil))
    }
}
