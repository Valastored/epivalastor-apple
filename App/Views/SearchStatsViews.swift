import SwiftUI

// MARK: - Recherche

enum SearchField: String, CaseIterable, Identifiable {
    case all = "Tout", subject = "Matière", teacher = "Prof", room = "Salle"
    var id: String { rawValue }
}

/// Résultats de la recherche (champ de recherche de la barre d'outils).
struct SearchResultsView: View {
    @EnvironmentObject private var store: ScheduleStore
    let query: String
    let onSelect: (Course) -> Void

    @State private var field: SearchField = .all
    @State private var examsOnly = false
    @State private var includePast = false

    private var results: [Course] {
        let q = normalizeForSearch(query.trimmingCharacters(in: .whitespaces))
        let now = store.now
        return store.data.courses // inclut les matières masquées : on doit pouvoir les retrouver
            .filter { includePast || $0.end > now }
            .filter { !examsOnly || $0.isExam }
            .filter { c in
                guard !q.isEmpty else { return true }
                let subject = normalizeForSearch(c.title)
                let teacher = normalizeForSearch(c.teacher)
                let room = normalizeForSearch(c.location)
                switch field {
                case .all: return subject.contains(q) || teacher.contains(q) || room.contains(q)
                case .subject: return subject.contains(q)
                case .teacher: return teacher.contains(q)
                case .room: return room.contains(q)
                }
            }
            .sorted { $0.start < $1.start }
            .prefix(300)
            .map { $0 }
    }

    var body: some View {
        let list = results
        let byDay = Dictionary(grouping: list, by: \.day)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Chercher dans", selection: $field) {
                    ForEach(SearchField.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                HStack(spacing: 10) {
                    Toggle("📝 Examens", isOn: $examsOnly).toggleStyle(.button)
                    Toggle("Cours passés", isOn: $includePast).toggleStyle(.button)
                    Spacer()
                    Text(list.isEmpty ? "Aucun résultat" : "\(list.count)\(list.count == 300 ? "+" : "") résultat\(list.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(byDay.keys.sorted(), id: \.self) { day in
                        Text(Fmt.dayLong(day)).font(.headline).padding(.top, 10)
                        ForEach(byDay[day] ?? []) { c in
                            CourseCardView(course: c).onTapGesture { onSelect(c) }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Statistiques

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "Cette semaine", nextWeek = "Semaine pro.", month = "Ce mois", all = "Tout"
    var id: String { rawValue }
}

struct StatsView: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var period: StatsPeriod = .week

    private struct Bar: Identifiable {
        let label: String
        let minutes: Int
        let color: Color
        var id: String { label }
    }

    /// Cours de la période — fériés et vacances exclus
    private var subset: [Course] {
        let cal = Calendar.current
        let monday = weekStart(store.now)
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday)!
        let afterNext = cal.date(byAdding: .day, value: 14, to: monday)!
        return store.visible.filter { c in
            if c.isHoliday { return false }
            switch period {
            case .week: return c.start >= monday && c.start < nextMonday
            case .nextWeek: return c.start >= nextMonday && c.start < afterNext
            case .month: return cal.isDate(c.start, equalTo: store.now, toGranularity: .month)
            case .all: return true
            }
        }
    }

    var body: some View {
        let courses = subset
        let now = store.now
        let total = courses.reduce(0) { $0 + $1.minutes }
        let done = courses.reduce(0) { acc, c in
            if now >= c.end { return acc + c.minutes }
            if now > c.start { return acc + Int(now.timeIntervalSince(c.start) / 60) }
            return acc
        }
        let days = Dictionary(grouping: courses, by: \.day)
        let bySubject = Dictionary(grouping: courses, by: \.title)
            .map { Bar(label: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }, color: $0.value[0].color) }
            .sorted { $0.minutes > $1.minutes }
        let byAgenda = Dictionary(grouping: courses, by: \.calendarName)
            .map { Bar(label: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }, color: Color(hex: $0.value[0].colorHex)) }
            .sorted { $0.minutes > $1.minutes }
        let busiest = days.max { a, b in a.value.reduce(0) { $0 + $1.minutes } < b.value.reduce(0) { $0 + $1.minutes } }

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Statistiques").font(.title2.bold())
                    Spacer()
                    Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
                }
                Picker("Période", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding()

            if courses.isEmpty {
                Text("Aucun cours sur cette période.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            tile("Heures", Fmt.minutes(total))
                            tile("Cours", "\(courses.count)")
                            tile("Jours", "\(days.count)")
                            tile("Examens", "\(courses.filter(\.isExam).count)", highlight: courses.contains(where: \.isExam))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Avancement").font(.headline)
                            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                                .tint(.accentViolet)
                            Text("\(Fmt.minutes(done)) faites · \(Fmt.minutes(max(0, total - done))) restantes (\(total > 0 ? done * 100 / total : 0) %)")
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        barSection("Heures par matière", bySubject)
                        if byAgenda.count > 1 { barSection("Heures par agenda", byAgenda) }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Journées").font(.headline)
                            if let b = busiest {
                                LabeledContent("Journée la plus chargée", value: "\(Fmt.dayLong(b.key)) · \(Fmt.minutes(b.value.reduce(0) { $0 + $1.minutes }))")
                            }
                            if let early = courses.min(by: { timeOfDay($0.start) < timeOfDay($1.start) }) {
                                LabeledContent("Début le plus tôt", value: "\(Fmt.time(early.start)) · \(early.title)")
                            }
                            if let late = courses.max(by: { timeOfDay($0.end) < timeOfDay($1.end) }) {
                                LabeledContent("Fin la plus tardive", value: "\(Fmt.time(late.end)) · \(late.title)")
                            }
                            LabeledContent("Moyenne par jour de cours", value: Fmt.minutes(days.isEmpty ? 0 : total / days.count))
                        }
                    }
                    .padding()
                }
            }
        }
        #if os(macOS)
        .frame(width: 640, height: 640)
        #endif
    }

    private func timeOfDay(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func tile(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).foregroundStyle(highlight ? Color.examRed : .primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(highlight ? Color.examRed.opacity(0.12) : Color.primary.opacity(0.06)))
    }

    private func barSection(_ title: String, _ bars: [Bar]) -> some View {
        let maxMinutes = max(1, bars.first?.minutes ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(bars) { bar in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(bar.label).lineLimit(1)
                        Spacer()
                        Text(Fmt.minutes(bar.minutes)).bold()
                    }
                    .font(.callout)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(bar.color).frame(width: max(4, geo.size.width * CGFloat(bar.minutes) / CGFloat(maxMinutes)))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}
