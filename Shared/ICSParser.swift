import Foundation

/// Un événement lu dans un fichier ICS.
struct ParsedEvent {
    var key: String
    var title: String
    var details: String
    var location: String
    var start: Date
    var end: Date
}

/// Lecteur ICS minimal : VEVENT, DTSTART/DTEND/DURATION (UTC, TZID, flottant, date seule),
/// RRULE DAILY/WEEKLY (INTERVAL, COUNT, UNTIL, BYDAY), EXDATE et RECURRENCE-ID.
enum ICSParser {

    private struct Prop {
        let name: String
        let params: [String: String]
        let value: String

        init?(line: String) {
            // Le « : » qui sépare l'en-tête de la valeur, hors guillemets
            var inQuotes = false
            var colon: String.Index?
            for i in line.indices {
                let ch = line[i]
                if ch == "\"" { inQuotes.toggle() }
                if ch == ":" && !inQuotes { colon = i; break }
            }
            guard let c = colon else { return nil }
            let head = line[..<c]
            value = String(line[line.index(after: c)...])
            let parts = head.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            name = parts[0].uppercased()
            var p: [String: String] = [:]
            for part in parts.dropFirst() {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { p[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            params = p
        }
    }

    // MARK: - Point d'entrée

    static func parse(_ raw: String, now: Date = Date()) -> [ParsedEvent] {
        // Dépliage des lignes (RFC 5545 : une ligne qui commence par espace/tab continue la précédente)
        let unfolded = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        var blocks: [[Prop]] = []
        var current: [Prop]?
        var nested = 0 // VALARM… dans un VEVENT
        for sub in unfolded.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(sub)
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" { current = []; nested = 0; continue }
            if upper == "END:VEVENT" {
                if let c = current { blocks.append(c) }
                current = nil
                continue
            }
            guard current != nil else { continue }
            if upper.hasPrefix("BEGIN:") { nested += 1; continue }
            if upper.hasPrefix("END:") { nested = max(0, nested - 1); continue }
            if nested > 0 { continue }
            if let p = Prop(line: line) { current?.append(p) }
        }

        // Occurrences redéfinies individuellement (RECURRENCE-ID) : à ne pas regénérer depuis la RRULE
        var overrides: [String: Set<Int>] = [:]
        for b in blocks {
            guard let uid = b.first(where: { $0.name == "UID" })?.value,
                  let rid = b.first(where: { $0.name == "RECURRENCE-ID" }),
                  let d = parseDate(rid) else { continue }
            overrides[uid, default: []].insert(Int(d.date.timeIntervalSince1970))
        }

        let windowStart = now.addingTimeInterval(-365 * 86400)
        let windowEnd = now.addingTimeInterval(365 * 86400)

        var result: [ParsedEvent] = []
        var usedKeys = Set<String>()

        for b in blocks {
            func first(_ n: String) -> Prop? { b.first { $0.name == n } }
            guard let dtStart = first("DTSTART"), let s = parseDate(dtStart) else { continue }
            let start = s.date

            var end: Date
            if let e = first("DTEND"), let ed = parseDate(e) {
                end = ed.date
            } else if let du = first("DURATION"), let secs = parseDuration(du.value) {
                end = start.addingTimeInterval(secs)
            } else {
                end = start.addingTimeInterval(s.dateOnly ? 86400 : 3600)
            }
            if end < start { end = start }

            let uid = first("UID")?.value
            let title = unescape(first("SUMMARY")?.value ?? "Sans titre")
            let details = unescape(first("DESCRIPTION")?.value ?? "")
            let location = unescape(first("LOCATION")?.value ?? "")

            func add(_ base: String, _ st: Date, _ en: Date) {
                var key = base
                if usedKeys.contains(key) { key = "\(base)#\(Int(st.timeIntervalSince1970))" }
                usedKeys.insert(key)
                result.append(ParsedEvent(key: key, title: title, details: details, location: location, start: st, end: en))
            }

            let base = uid ?? title
            if let rid = first("RECURRENCE-ID"), let rd = parseDate(rid) {
                add("\(base)#\(Int(rd.date.timeIntervalSince1970))", start, end)
            } else if let rr = first("RRULE") {
                let rule = parseRule(rr.value)
                let tz = timeZone(for: dtStart)
                let duration = end.timeIntervalSince(start)
                var excluded = Set<Int>()
                for ex in b where ex.name == "EXDATE" {
                    for v in ex.value.split(separator: ",") {
                        if let d = parseDateValue(String(v), params: ex.params) { excluded.insert(Int(d.date.timeIntervalSince1970)) }
                    }
                }
                let skip = overrides[uid ?? ""] ?? []
                for occ in expand(start: start, rule: rule, tz: tz, windowStart: windowStart, windowEnd: windowEnd) {
                    let t = Int(occ.timeIntervalSince1970)
                    if excluded.contains(t) || skip.contains(t) { continue }
                    add("\(base)#\(t)", occ, occ.addingTimeInterval(duration))
                }
            } else {
                add(uid ?? "\(title)#\(Int(start.timeIntervalSince1970))", start, end)
            }
        }
        return result
    }

    // MARK: - Dates

    private static func timeZone(for p: Prop) -> TimeZone {
        if p.value.hasSuffix("Z") { return TimeZone(identifier: "UTC")! }
        if let id = p.params["TZID"] {
            if let tz = TimeZone(identifier: id) { return tz }
            // Noms Windows fréquents dans les exports Outlook
            let lower = id.lowercased()
            if lower.contains("romance") || lower.contains("w. europe") || lower.contains("paris") {
                return TimeZone(identifier: "Europe/Paris")!
            }
        }
        return .current
    }

    private static func parseDate(_ p: Prop) -> (date: Date, dateOnly: Bool)? {
        parseDateValue(p.value, params: p.params)
    }

    private static func parseDateValue(_ raw: String, params: [String: String]) -> (date: Date, dateOnly: Bool)? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        let isUTC = v.hasSuffix("Z")
        let digits = Array(v.replacingOccurrences(of: "Z", with: ""))
        guard digits.count >= 8 else { return nil }

        func num(_ a: Int, _ b: Int) -> Int? {
            guard b <= digits.count else { return nil }
            return Int(String(digits[a..<b]))
        }

        var cal = Calendar(identifier: .gregorian)
        if isUTC {
            cal.timeZone = TimeZone(identifier: "UTC")!
        } else if let id = params["TZID"] {
            cal.timeZone = TimeZone(identifier: id)
                ?? ((id.lowercased().contains("romance") || id.lowercased().contains("europe")) ? TimeZone(identifier: "Europe/Paris")! : .current)
        } else {
            cal.timeZone = .current
        }

        var comps = DateComponents()
        comps.year = num(0, 4); comps.month = num(4, 6); comps.day = num(6, 8)
        let dateOnly = params["VALUE"]?.uppercased() == "DATE" || digits.count == 8
        if !dateOnly, digits.count >= 13, digits[8] == "T" {
            comps.hour = num(9, 11); comps.minute = num(11, 13); comps.second = num(13, 15) ?? 0
        } else {
            comps.hour = 0; comps.minute = 0; comps.second = 0
            cal.timeZone = .current // une date seule = minuit heure locale
        }
        guard let d = cal.date(from: comps) else { return nil }
        return (d, dateOnly)
    }

    /// « PT1H30M », « P1D », « -PT15M »…
    private static func parseDuration(_ raw: String) -> TimeInterval? {
        var s = raw.uppercased()
        var sign: Double = 1
        if s.hasPrefix("-") { sign = -1; s.removeFirst() }
        if s.hasPrefix("+") { s.removeFirst() }
        guard s.hasPrefix("P") else { return nil }
        var total: Double = 0
        var number = ""
        for ch in s.dropFirst() {
            if ch.isNumber { number.append(ch); continue }
            let n = Double(number) ?? 0
            number = ""
            switch ch {
            case "W": total += n * 7 * 86400
            case "D": total += n * 86400
            case "H": total += n * 3600
            case "M": total += n * 60
            case "S": total += n
            default: break // « T »
            }
        }
        return sign * total
    }

    // MARK: - Récurrences

    private static func parseRule(_ raw: String) -> [String: String] {
        var rule: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { rule[kv[0].uppercased()] = kv[1] }
        }
        return rule
    }

    /// Calendar.weekday : 1 = dimanche … 7 = samedi
    private static func weekday(_ code: String) -> Int? {
        switch code.suffix(2).uppercased() {
        case "SU": return 1
        case "MO": return 2
        case "TU": return 3
        case "WE": return 4
        case "TH": return 5
        case "FR": return 6
        case "SA": return 7
        default: return nil
        }
    }

    private static func expand(start: Date, rule: [String: String], tz: TimeZone, windowStart: Date, windowEnd: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        cal.firstWeekday = 2 // lundi

        let interval = max(1, Int(rule["INTERVAL"] ?? "1") ?? 1)
        let count = rule["COUNT"].flatMap { Int($0) }
        let until = rule["UNTIL"].flatMap { parseDateValue($0, params: [:])?.date }
        var results: [Date] = []
        var produced = 0

        func accept(_ d: Date) -> Bool { // false = on arrête
            if let u = until, d > u { return false }
            if d > windowEnd { return false }
            produced += 1
            if let c = count, produced > c { return false }
            if d >= windowStart { results.append(d) }
            return true
        }

        switch rule["FREQ"]?.uppercased() {
        case "DAILY":
            var i = 0
            while i < 5000, let d = cal.date(byAdding: .day, value: i * interval, to: start), accept(d) { i += 1 }

        case "WEEKLY":
            let days = (rule["BYDAY"]?.split(separator: ",").compactMap { weekday(String($0)) } ?? [cal.component(.weekday, from: start)])
                .sorted { ($0 + 5) % 7 < ($1 + 5) % 7 } // ordre lundi → dimanche
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: start)?.start else { return [start] }
            let time = cal.dateComponents([.hour, .minute, .second], from: start)
            var w = 0
            outer: while w < 2000 {
                guard let ws = cal.date(byAdding: .weekOfYear, value: w * interval, to: weekStart) else { break }
                if ws > windowEnd { break }
                for wd in days {
                    guard let dayDate = cal.date(byAdding: .day, value: (wd + 5) % 7, to: ws),
                          let d = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: dayDate)
                    else { continue }
                    if d < start { continue }
                    if !accept(d) { break outer }
                }
                w += 1
            }

        default:
            // MONTHLY / YEARLY : rares dans les emplois du temps, on garde la première occurrence
            results = [start]
        }
        return results
    }

    // MARK: - Texte

    private static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for ch in s {
            if escaping {
                switch ch {
                case "n", "N": out.append("\n")
                default: out.append(ch) // \, \; \\
                }
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                out.append(ch)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
