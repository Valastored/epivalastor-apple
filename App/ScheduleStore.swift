import Foundation
import SwiftUI
import WidgetKit
#if os(macOS)
import AppKit
import EventKit
#endif

/// État de l'app : agendas, cours, changements, synchro. Partagé par toutes les fenêtres et la barre des menus.
@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var visible: [Course] = []   // cours affichés (fusionnés, sans matières masquées)
    @Published private(set) var isSyncing = false
    @Published var syncError: String?
    @Published private(set) var now = Date()              // horloge (toutes les 30 s)

    /// Appelé après chaque enregistrement (cours modifiés) — l'iPhone s'en sert pour les notifications.
    var onDataChanged: (@MainActor () -> Void)?
    /// Appelé avec les nouveaux changements détectés par une synchro.
    var onNewChanges: (@MainActor ([ScheduleChange]) -> Void)?

    private var clockTimer: Timer?
    private var syncTimer: Timer?

    init() {
        data = SharedStore.load()
        visible = visibleCourses(from: data)

        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        // Synchro automatique toutes les heures tant que l'app tourne (elle reste dans la barre des menus)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
        Task { await sync() }
        refreshWidget()

        #if os(macOS)
        // Au réveil du Mac : on relance le widget (souvent figé après une veille) et on resynchronise
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWidget()
                await self?.sync()
            }
        }
        #endif
    }

    var unseenChangesCount: Int { data.changes.filter { !$0.seen }.count }

    // MARK: - Sauvegarde

    private func persist() {
        data.courses.sort { $0.start < $1.start }
        SharedStore.save(data)
        visible = visibleCourses(from: data)
        reloadWidgetIfNeeded()
        #if os(macOS)
        let courses = visible
        Task { await CalendarSync.shared.sync(courses) }
        #endif
        onDataChanged?()
    }

    // MARK: - Widget

    private var lastWidgetSignature = 0

    /// Recharge le widget seulement si les cours ont changé. WidgetKit limite le nombre de rechargements
    /// par jour : en rechargeant à chaque synchro (toutes les heures), le widget finissait figé ou désactivé
    /// jusqu'à ce qu'on change sa taille.
    private func reloadWidgetIfNeeded(force: Bool = false) {
        var hasher = Hasher()
        for c in visible { hasher.combine(c.signature); hasher.combine(c.calendarName); hasher.combine(c.colorHex) }
        let sig = hasher.finalize()
        guard force || sig != lastWidgetSignature else { return }
        lastWidgetSignature = sig
        WidgetCenter.shared.reloadTimelines(ofKind: "NextCourse")
    }

    /// Force le rechargement du widget (lancement de l'app, réveil du Mac, bouton dans les réglages).
    func refreshWidget() {
        reloadWidgetIfNeeded(force: true)
    }

    // MARK: - Agendas

    func addLink(url: String, name: String, colorHex: String) {
        data.links.append(IcsLink(url: url.trimmingCharacters(in: .whitespaces), name: name.trimmingCharacters(in: .whitespaces), colorHex: colorHex))
        persist()
        Task { await sync(force: true) }
    }

    func updateLink(_ link: IcsLink, url: String, name: String, colorHex: String) {
        guard let idx = data.links.firstIndex(where: { $0.id == link.id }) else { return }
        let newName = name.trimmingCharacters(in: .whitespaces)
        let newURL = url.trimmingCharacters(in: .whitespaces)
        // Nouvelle URL = autre agenda : on retire les cours futurs pour ne pas inventer de faux changements
        if newURL != link.url {
            let now = Date()
            data.courses.removeAll { $0.calendarName == link.name && $0.start >= now }
        }
        for i in data.courses.indices where data.courses[i].calendarName == link.name {
            data.courses[i].calendarName = newName
            data.courses[i].colorHex = colorHex
        }
        for i in data.changes.indices where data.changes[i].calendarName == link.name {
            data.changes[i].calendarName = newName
            data.changes[i].colorHex = colorHex
        }
        data.links[idx] = IcsLink(id: link.id, url: newURL, name: newName, colorHex: colorHex)
        persist()
        Task { await sync(force: true) }
    }

    func removeLink(_ link: IcsLink) {
        data.links.removeAll { $0.id == link.id }
        data.courses.removeAll { $0.calendarName == link.name }
        data.changes.removeAll { $0.calendarName == link.name }
        persist()
    }

    // MARK: - Matières masquées / changements

    func hideSubject(_ title: String) { data.hiddenSubjects.insert(title); persist() }
    func unhideSubject(_ title: String) { data.hiddenSubjects.remove(title); persist() }

    func markChangesSeen() {
        guard data.changes.contains(where: { !$0.seen }) else { return }
        for i in data.changes.indices { data.changes[i].seen = true }
        persist()
    }

    /// Couleur actuelle d'un agenda (pour colorer « EPITA & GDG » nom par nom)
    func color(ofCalendar name: String) -> Color? {
        data.links.first { $0.name == name }.map { Color(hex: $0.colorHex) }
    }

    // MARK: - Synchro

    func sync(force: Bool = false) async {
        if isSyncing && !force { return }
        while isSyncing { try? await Task.sleep(nanoseconds: 200_000_000) } // une synchro à la fois
        isSyncing = true
        defer { isSyncing = false }

        var failures = 0
        let changesBefore = Set(data.changes.map(\.id))
        let links = data.links
        for link in links {
            let urlString = link.url.replacingOccurrences(of: "webcal://", with: "https://")
            guard let url = URL(string: urlString) else { failures += 1; continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                let (raw, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let text = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1),
                      text.contains("BEGIN:VCALENDAR")
                else { failures += 1; continue }
                // L'agenda a pu être supprimé / modifié pendant le téléchargement
                guard let current = data.links.first(where: { $0.id == link.id }), current.url == link.url else { continue }
                merge(link: current, parsed: ICSParser.parse(text))
            } catch {
                failures += 1
            }
        }

        let now = Date()
        data.changes.removeAll { $0.detectedAt < now.addingTimeInterval(-14 * 86400) }
        if data.links.isEmpty || failures < data.links.count { data.lastSync = now }
        let fresh = data.changes.filter { !changesBefore.contains($0.id) }
        if !fresh.isEmpty { onNewChanges?(fresh) }
        syncError = failures > 0 ? "Synchronisation impossible pour \(failures) agenda\(failures > 1 ? "s" : "") : les cours déjà enregistrés sont conservés." : nil
        persist()
    }

    /// Fusionne un agenda téléchargé : cours futurs remplacés (avec détection des changements),
    /// cours passés complétés sans jamais être supprimés.
    private func merge(link: IcsLink, parsed: [ParsedEvent]) {
        let now = Date()
        let all = parsed.map {
            Course(title: $0.title, details: $0.details, location: $0.location, start: $0.start, end: $0.end,
                   colorHex: link.colorHex, calendarName: link.name, eventKey: $0.key)
        }
        let existing = data.courses.filter { $0.calendarName == link.name }

        // Première synchro de cet agenda : on garde tout, y compris le passé
        if existing.isEmpty {
            data.courses += all
            return
        }

        let oldFuture = existing.filter { $0.start >= now }
        let newFuture = all.filter { $0.start >= now }
        if !oldFuture.isEmpty {
            let changes = ChangeDetector.detect(old: oldFuture, new: newFuture, link: link, now: now)
            data.changes.insert(contentsOf: changes, at: 0)
        }
        data.courses.removeAll { $0.calendarName == link.name && $0.start >= now }
        data.courses += newFuture

        // Historique : on ajoute les cours passés qui manquent
        let pastExisting = existing.filter { $0.start < now }
        let signatures = Set(pastExisting.map { "\($0.title)|\(Int($0.start.timeIntervalSince1970))|\(Int($0.end.timeIntervalSince1970))" })
        let keys = Set(pastExisting.map(\.eventKey).filter { !$0.isEmpty })
        data.courses += all.filter {
            $0.start < now
                && !signatures.contains("\($0.title)|\(Int($0.start.timeIntervalSince1970))|\(Int($0.end.timeIntervalSince1970))")
                && ($0.eventKey.isEmpty || !keys.contains($0.eventKey))
        }
    }
}

#if os(macOS)
// MARK: - Synchro avec l'app Calendrier du Mac

/// Copie les cours dans un calendrier « EpiValastor » de l'app Calendrier (iCloud si possible, sinon « Sur mon Mac »).
/// Les événements sont reconnus par leur URL epivalastor://… : seuls ceux qui ont changé sont modifiés.
@MainActor
final class CalendarSync: ObservableObject {
    static let shared = CalendarSync()
    nonisolated static let enabledKey = "calendarSyncEnabled"
    nonisolated static let calendarTitle = "EpiValastor"

    @Published private(set) var status = ""
    @Published private(set) var isWorking = false

    private let eventStore = EKEventStore()
    private let calendarIDKey = "calendarSyncID"
    private var lastSignature = 0
    private var pending: [Course]?

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        if authorized { return true }
        let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        if !granted {
            status = "Accès refusé. Autorise EpiValastor dans Réglages Système › Confidentialité et sécurité › Calendriers."
        }
        return granted
    }

    /// Met le calendrier à jour (ne fait rien si l'option est désactivée ou si rien n'a changé).
    func sync(_ courses: [Course], force: Bool = false) async {
        guard enabled else { return }
        if isWorking { pending = courses; return }

        var hasher = Hasher()
        for c in courses { hasher.combine(c.signature); hasher.combine(c.details) }
        let sig = hasher.finalize()
        guard force || sig != lastSignature else { return }

        isWorking = true
        defer {
            isWorking = false
            if let next = pending { pending = nil; Task { await self.sync(next) } }
        }

        guard await requestAccess() else { return }
        guard let calendar = calendar(create: true) else {
            status = "Impossible de créer le calendrier « \(Self.calendarTitle) »."
            return
        }

        let cal = Calendar.current
        let now = Date()
        let from = cal.date(byAdding: .day, value: -30, to: now)!
        let to = cal.date(byAdding: .day, value: 180, to: now)!

        var wanted: [String: Course] = [:]
        for c in courses where c.end > from && c.start < to { wanted[Self.key(for: c)] = c }

        var existing: [String: EKEvent] = [:]
        var added = 0, updated = 0, removed = 0
        let predicate = eventStore.predicateForEvents(withStart: from, end: to.addingTimeInterval(86400), calendars: [calendar])
        for event in eventStore.events(matching: predicate) {
            let key = event.url?.absoluteString ?? ""
            if wanted[key] != nil, existing[key] == nil {
                existing[key] = event
            } else if event.startDate >= from {
                // Cours supprimé de l'agenda, matière masquée ou doublon
                try? eventStore.remove(event, span: .thisEvent, commit: false)
                removed += 1
            }
        }

        for (key, course) in wanted {
            if let event = existing[key] {
                if apply(course, to: event) {
                    try? eventStore.save(event, span: .thisEvent, commit: false)
                    updated += 1
                }
            } else {
                let event = EKEvent(eventStore: eventStore)
                event.calendar = calendar
                event.url = URL(string: key)
                _ = apply(course, to: event)
                try? eventStore.save(event, span: .thisEvent, commit: false)
                added += 1
            }
        }

        do {
            try eventStore.commit()
            lastSignature = sig
            var parts = ["\(wanted.count) cours"]
            if added + updated + removed > 0 { parts.append("+\(added) / ~\(updated) / −\(removed)") }
            status = "À jour à \(Fmt.time(Date())) · " + parts.joined(separator: " · ")
        } catch {
            eventStore.reset()
            status = "Erreur d'écriture dans Calendrier : \(error.localizedDescription)"
        }
    }

    /// Supprime le calendrier « EpiValastor » (et tous ses événements) de l'app Calendrier.
    func removeCalendar() {
        guard authorized, let calendar = calendar(create: false) else { return }
        do {
            try eventStore.removeCalendar(calendar, commit: true)
            UserDefaults.standard.removeObject(forKey: calendarIDKey)
            lastSignature = 0
            status = "Calendrier « \(Self.calendarTitle) » supprimé."
        } catch {
            status = "Suppression impossible : \(error.localizedDescription)"
        }
    }

    // MARK: Détails

    private static func key(for c: Course) -> String {
        let raw = "\(c.eventKey.isEmpty ? c.title : c.eventKey)|\(Int(c.start.timeIntervalSince1970))"
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(raw.hashValue)
        return "epivalastor://event/\(encoded)"
    }

    /// Recopie le cours dans l'événement ; renvoie true si quelque chose a changé.
    private func apply(_ c: Course, to event: EKEvent) -> Bool {
        let cal = Calendar.current
        let allDay = c.isHoliday
        let title = c.isExam ? "📝 \(c.title)" : c.title
        let location: String? = c.location.isEmpty ? nil : c.location
        let notes = (c.details.isEmpty ? "" : c.details + "\n\n") + "Agenda : \(c.calendarName)"
        var start = c.start
        var end = c.end
        if allDay {
            // Fériés / vacances : journées entières
            start = cal.startOfDay(for: c.start)
            end = max(start, cal.startOfDay(for: c.end.addingTimeInterval(-1)))
        }

        var changed = false
        if event.title != title { event.title = title; changed = true }
        if event.location != location { event.location = location; changed = true }
        if event.notes != notes { event.notes = notes; changed = true }
        if event.isAllDay != allDay { event.isAllDay = allDay; changed = true }
        if event.startDate != start { event.startDate = start; changed = true }
        if event.endDate != end { event.endDate = end; changed = true }
        return changed
    }

    private func calendar(create: Bool) -> EKCalendar? {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: calendarIDKey), let c = eventStore.calendar(withIdentifier: id) { return c }
        if let c = eventStore.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            defaults.set(c.calendarIdentifier, forKey: calendarIDKey)
            return c
        }
        guard create else { return nil }

        // iCloud d'abord (visible aussi sur l'iPhone), puis le compte par défaut, puis « Sur mon Mac »
        var sources: [EKSource] = []
        sources += eventStore.sources.filter { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
        if let s = eventStore.defaultCalendarForNewEvents?.source { sources.append(s) }
        sources += eventStore.sources.filter { $0.sourceType == .local }
        for source in sources {
            let c = EKCalendar(for: .event, eventStore: eventStore)
            c.title = Self.calendarTitle
            c.color = NSColor(red: 0.48, green: 0.12, blue: 0.64, alpha: 1)
            c.source = source
            if (try? eventStore.saveCalendar(c, commit: true)) != nil {
                defaults.set(c.calendarIdentifier, forKey: calendarIDKey)
                return c
            }
        }
        return nil
    }
}
#endif
