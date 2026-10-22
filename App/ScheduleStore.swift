import Foundation
import SwiftUI
import WidgetKit

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
    }

    var unseenChangesCount: Int { data.changes.filter { !$0.seen }.count }

    // MARK: - Sauvegarde

    private func persist() {
        data.courses.sort { $0.start < $1.start }
        SharedStore.save(data)
        visible = visibleCourses(from: data)
        WidgetCenter.shared.reloadAllTimelines()
        onDataChanged?()
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
