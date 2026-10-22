import Foundation

/// Lecture / écriture des données dans le conteneur partagé (App Group) entre l'app et le widget.
enum SharedStore {
    /// Identifiant de l'App Group, défini dans Info.plist (clé AppGroupID).
    static var appGroupID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    static var directory: URL {
        if let id = appGroupID,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        // Repli (pas d'équipe de signature) : dossier Application Support de l'app — le widget ne verra pas les données
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpiValastor", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var fileURL: URL { directory.appendingPathComponent("schedule.json") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func load() -> AppData {
        guard let raw = try? Data(contentsOf: fileURL),
              let data = try? decoder.decode(AppData.self, from: raw) else { return AppData() }
        return data
    }

    static func save(_ data: AppData) {
        guard let raw = try? encoder.encode(data) else { return }
        try? raw.write(to: fileURL, options: .atomic)
    }
}
