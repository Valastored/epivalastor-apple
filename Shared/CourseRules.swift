import Foundation
import SwiftUI

// MARK: - Détection examens / fériés / vacances

private let examRegex = try! NSRegularExpression(
    pattern: "(?<![\\p{L}\\d])(examens?|exams?|partiels?|qcm|contr[ôo]les?|ds|soutenances?|rattrapages?|midterms?|[ée]valuations?|interros?|interrogations?)(?![\\p{L}\\d])",
    options: [.caseInsensitive]
)
private let holidayRegex = try! NSRegularExpression(
    pattern: "(?<![\\p{L}\\d])(f[ée]ri[ée]s?|vacances|cong[ée]s?|holidays?)(?![\\p{L}\\d])",
    options: [.caseInsensitive]
)

private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

func normalizeForSearch(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
}

extension Course {
    /// Jour férié ou vacances : pas un vrai cours (exclu des stats, du widget et de la barre des menus).
    var isHoliday: Bool { matches(holidayRegex, title) }

    var holidayLabel: String {
        let t = normalizeForSearch(title)
        return (t.contains("vacances") || t.contains("conge")) ? "🌴 Vacances" : "🎉 Férié"
    }

    /// Partiel, QCM, contrôle, soutenance…
    var isExam: Bool {
        if isHoliday { return false }
        if matches(examRegex, title) { return true }
        return details.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("type") && matches(examRegex, $0)
        }
    }

    /// Nom du prof (ligne « Enseignant : … » de la description).
    var teacher: String {
        guard let line = details.components(separatedBy: .newlines).first(where: {
            $0.localizedCaseInsensitiveContains("enseignant") || $0.localizedCaseInsensitiveContains("intervenant")
        }), let idx = line.firstIndex(of: ":") else { return "" }
        return line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
    }

    var displayLocation: String {
        (location.isEmpty || location == "Non spécifié") ? "" : location
    }

    var isAllDay: Bool { end.timeIntervalSince(start) >= 20 * 3600 }
    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    var day: Date { Calendar.current.startOfDay(for: start) }

    func isOngoing(at now: Date) -> Bool { now >= start && now < end }

    func progress(at now: Date) -> Double? {
        guard isOngoing(at: now), end > start else { return nil }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    var signature: String { "\(title)|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))|\(location)" }
}

// MARK: - Listes de cours

/// Fusionne les cours présents dans plusieurs agendas et retire les matières masquées.
func visibleCourses(from data: AppData) -> [Course] {
    var merged: [String: Course] = [:]
    var order: [String] = []
    for c in data.courses where !data.hiddenSubjects.contains(c.title) {
        let key = "\(c.title)|\(Int(c.start.timeIntervalSince1970))"
        if var existing = merged[key] {
            let names = existing.calendarName.components(separatedBy: " & ")
            if !names.contains(c.calendarName) { existing.calendarName += " & \(c.calendarName)" }
            merged[key] = existing
        } else {
            merged[key] = c
            order.append(key)
        }
    }
    return order.compactMap { merged[$0] }.sorted { $0.start < $1.start }
}

/// Cours en cours et prochain cours (fériés / vacances ignorés).
func currentAndNext(_ courses: [Course], at now: Date) -> (current: Course?, next: Course?) {
    let real = courses.filter { !$0.isHoliday }
    let current = real.first { $0.isOngoing(at: now) }
    let next = real.first { $0.start > now }
    return (current, next)
}

/// Élément d'une journée : un cours ou une pause.
enum DayItem: Identifiable {
    case course(Course)
    case pause(id: String, label: String)

    var id: String {
        switch self {
        case .course(let c): return c.id
        case .pause(let id, _): return id
        }
    }
}

/// Cours d'une journée avec les pauses de 30 min ou plus entre eux.
func dayItems(_ courses: [Course]) -> [DayItem] {
    let sorted = courses.sorted { $0.start < $1.start }
    var items: [DayItem] = []
    let cal = Calendar.current
    for (i, c) in sorted.enumerated() {
        items.append(.course(c))
        guard i + 1 < sorted.count else { continue }
        let next = sorted[i + 1]
        let gap = Int(next.start.timeIntervalSince(c.end) / 60)
        if gap >= 30, cal.isDate(c.end, inSameDayAs: next.start) {
            let hour = cal.component(.hour, from: c.end)
            let type = (11...13).contains(hour) ? "Midi" : (hour >= 18 ? "du soir" : "Inter-cours")
            items.append(.pause(id: "pause-\(c.id)", label: "Pause \(type) · \(Fmt.minutes(gap))"))
        }
    }
    return items
}

// MARK: - Formats

enum Fmt {
    static let locale = Locale(identifier: "fr_FR")

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = pattern
        return f
    }

    private static let timeF = formatter("HH:mm")
    private static let dayLongF = formatter("EEEE d MMMM")
    private static let dayShortF = formatter("EEE dd/MM")
    private static let dayNumF = formatter("dd.MM")
    private static let monthF = formatter("MMMM yyyy")
    private static let fullF = formatter("EEEE d MMMM 'à' HH:mm")

    static func time(_ d: Date) -> String { timeF.string(from: d) }
    static func dayLong(_ d: Date) -> String { dayLongF.string(from: d).capitalizedFirst }
    static func dayShort(_ d: Date) -> String { dayShortF.string(from: d) }
    static func dayNum(_ d: Date) -> String { dayNumF.string(from: d) }
    static func month(_ d: Date) -> String { monthF.string(from: d).capitalizedFirst }
    static func full(_ d: Date) -> String { fullF.string(from: d).capitalizedFirst }

    /// 90 → « 1 h 30 », 45 → « 45 min »
    static func minutes(_ total: Int) -> String {
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return String(format: "%d h %02d", h, m)
    }

    /// Temps restant arrondi à la minute supérieure
    static func remaining(_ seconds: TimeInterval) -> String {
        minutes(max(0, Int((seconds + 59) / 60)))
    }

    /// « aujourd'hui », « demain » ou « lun 27/10 »
    static func relativeDay(_ d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tomorrow) { return "demain" }
        return dayShort(d)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Couleurs

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 8 { s = String(s.dropFirst(2)) } // AARRGGBB → RRGGBB
        let v = UInt64(s, radix: 16) ?? 0x9C27B0
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    static let examRed = Color(red: 0.83, green: 0.18, blue: 0.18)
    static let holidayTeal = Color(red: 0.0, green: 0.65, blue: 0.65)
    static let accentViolet = Color(red: 0.61, green: 0.15, blue: 0.69)
}

/// Couleurs proposées pour les agendas (mêmes que sur Android)
let agendaPalette = ["EA4335", "4285F4", "FF9800", "34A853", "9C27B0", "00ACC1"]

extension Course {
    var color: Color {
        if isHoliday { return .holidayTeal }
        if isExam { return .examRed }
        return Color(hex: colorHex)
    }
}
