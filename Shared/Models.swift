import Foundation

/// Un cours (ou un événement) issu d'un agenda ICS.
struct Course: Codable, Hashable, Identifiable {
    var title: String
    var details: String      // DESCRIPTION de l'ICS
    var location: String
    var start: Date
    var end: Date
    var colorHex: String
    var calendarName: String // nom de l'agenda (ou « A & B » si le cours est dans plusieurs agendas)
    var eventKey: String     // identifiant stable (UID ICS + date d'origine pour les récurrences)

    var id: String { "\(calendarName)|\(title)|\(Int(start.timeIntervalSince1970))|\(eventKey)" }
}

/// Un agenda ajouté par l'utilisateur.
struct IcsLink: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var url: String
    var name: String
    var colorHex: String
}

enum ChangeType: String, Codable { case added, removed, modified }

/// Un changement détecté lors d'une synchro (cours ajouté, annulé ou modifié).
struct ScheduleChange: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var calendarName: String
    var colorHex: String
    var type: ChangeType
    var title: String
    var oldTitle: String?
    var oldStart: Date?
    var oldEnd: Date?
    var newStart: Date?
    var newEnd: Date?
    var oldLocation: String?
    var newLocation: String?
    var detectedAt: Date
    var seen: Bool = false
}

/// Toutes les données de l'app, enregistrées dans un fichier JSON partagé avec le widget.
struct AppData: Codable {
    var links: [IcsLink] = []
    var courses: [Course] = []
    var changes: [ScheduleChange] = []
    var hiddenSubjects: Set<String> = []
    var lastSync: Date?

    init() {}

    // Décodage tolérant : un champ absent (ancienne version du fichier) prend sa valeur par défaut
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        links = try c.decodeIfPresent([IcsLink].self, forKey: .links) ?? []
        courses = try c.decodeIfPresent([Course].self, forKey: .courses) ?? []
        changes = try c.decodeIfPresent([ScheduleChange].self, forKey: .changes) ?? []
        hiddenSubjects = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenSubjects) ?? []
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
    }
}
