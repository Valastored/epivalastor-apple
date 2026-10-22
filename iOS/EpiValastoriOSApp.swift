import SwiftUI
import BackgroundTasks
import UserNotifications

extension ScheduleStore {
    /// Instance unique (partagée avec la synchro en arrière-plan)
    static let shared = ScheduleStore()
}

let backgroundRefreshID = "com.valastor.epivalastor.refresh"

@main
struct EpiValastoriOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ScheduleStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme") private var theme = "system"

    init() {
        let store = ScheduleStore.shared
        // Après chaque modification : notifications + Live Activity à jour
        store.onDataChanged = { PhoneServices.refresh(store) }
        store.onNewChanges = { changes in NotificationManager.notifyChanges(changes, hidden: store.data.hiddenSubjects) }
        NotificationManager.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(store)
                .preferredColorScheme(theme == "dark" ? .dark : (theme == "light" ? .light : nil))
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await store.sync() }
                PhoneServices.refresh(store)
            case .background:
                scheduleBackgroundRefresh()
            default:
                break
            }
        }
        // Synchro en arrière-plan (Android : WorkManager vers 6 h)
        .backgroundTask(.appRefresh(backgroundRefreshID)) {
            await ScheduleStore.shared.sync()
            await MainActor.run { PhoneServices.refresh(ScheduleStore.shared) }
            scheduleBackgroundRefresh()
        }
    }
}

/// Demande à iOS une synchro vers 6 h du matin (iOS choisit le moment exact selon l'usage du téléphone).
func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshID)
    let cal = Calendar.current
    var next = cal.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()
    if next <= Date() { next = cal.date(byAdding: .day, value: 1, to: next) ?? Date().addingTimeInterval(86400) }
    request.earliestBeginDate = next
    try? BGTaskScheduler.shared.submit(request)
}

/// Tout ce qui doit suivre les cours : rappels programmés et Live Activity.
@MainActor
enum PhoneServices {
    static func refresh(_ store: ScheduleStore) {
        let defaults = UserDefaults.standard
        let courses = store.visible
        NotificationManager.reschedule(
            courses: courses,
            remindersOn: defaults.object(forKey: "remindersOn") as? Bool ?? true,
            reminderMinutes: defaults.object(forKey: "reminderMinutes") as? Int ?? 15,
            examOn: defaults.object(forKey: "examNotifOn") as? Bool ?? true
        )
        LiveActivityManager.update(courses: courses, enabled: defaults.object(forKey: "liveActivityOn") as? Bool ?? true)
    }
}

/// Affiche les notifications même app ouverte, et ouvre la liste des changements quand on touche la notification.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["openChanges"] as? Bool == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .openChanges, object: nil)
            }
        }
        completionHandler()
    }
}
