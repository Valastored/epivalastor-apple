import WidgetKit
import SwiftUI

// MARK: - Données du widget

struct CourseEntry: TimelineEntry {
    let date: Date
    let current: Course?
    let next: Course?
    let laterToday: [Course]   // cours suivants de la même journée
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CourseEntry {
        let now = Date()
        let sample = Course(title: "Algorithmique", details: "", location: "Salle 302", start: now.addingTimeInterval(1500),
                            end: now.addingTimeInterval(1500 + 5400), colorHex: "9C27B0", calendarName: "EPITA", eventKey: "demo")
        return CourseEntry(date: now, current: nil, next: sample, laterToday: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (CourseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date(), courses: loadCourses()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CourseEntry>) -> Void) {
        let now = Date()
        let courses = loadCourses()
        // Une entrée à chaque moment où l'affichage change : 1 h avant, début, fin de chaque cours
        var dates: Set<Date> = [now]
        let horizon = now.addingTimeInterval(36 * 3600)
        for c in courses where c.end > now && c.start < horizon {
            for d in [c.start.addingTimeInterval(-3600), c.start, c.end] where d > now && d < horizon { dates.insert(d) }
        }
        let entries = dates.sorted().prefix(60).map { entry(at: $0, courses: courses) }
        completion(Timeline(entries: Array(entries), policy: .after(min(entries.last?.date ?? now, now.addingTimeInterval(3600)).addingTimeInterval(60))))
    }

    private func loadCourses() -> [Course] {
        visibleCourses(from: SharedStore.load()).filter { !$0.isHoliday }
    }

    private func entry(at date: Date, courses: [Course]) -> CourseEntry {
        let pair = currentAndNext(courses, at: date)
        let shown = pair.current ?? pair.next
        let later = courses.filter {
            guard let s = shown else { return false }
            return $0.start > s.start && Calendar.current.isDate($0.start, inSameDayAs: s.start)
        }
        return CourseEntry(date: date, current: pair.current, next: pair.next, laterToday: Array(later.prefix(5)))
    }
}

// MARK: - Vues

/// Libellé + valeur de droite : compte à rebours dans la dernière heure, sinon l'heure du cours.
private struct WhenView: View {
    let entry: CourseEntry
    let course: Course
    let big: Bool

    var body: some View {
        let ongoing = entry.current != nil
        let target = ongoing ? course.end : course.start
        let secs = target.timeIntervalSince(entry.date)
        VStack(alignment: .trailing, spacing: 0) {
            if secs <= 3600 {
                Text(ongoing ? "reste" : "dans").font(.caption2).foregroundStyle(.secondary)
                Text(target, style: .timer)
                    .font(big ? .title2.bold() : .headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentViolet)
                    .multilineTextAlignment(.trailing)
            } else {
                let rel = Fmt.relativeDay(course.start, now: entry.date)
                Text(ongoing ? "fin" : (rel.isEmpty ? "à" : rel)).font(.caption2).foregroundStyle(.secondary)
                Text(Fmt.time(target))
                    .font(big ? .title2.bold() : .headline)
                    .foregroundStyle(Color.accentViolet)
            }
        }
    }
}

struct EpiValastorWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CourseEntry

    var body: some View {
        if let course = entry.current ?? entry.next {
            switch family {
            case .systemSmall: small(course)
            case .systemLarge: large(course)
            #if os(iOS)
            case .accessoryRectangular: accessoryRect(course)
            case .accessoryInline: accessoryInline(course)
            case .accessoryCircular: accessoryCircle(course)
            #endif
            default: medium(course)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "sun.max").font(.title2).foregroundStyle(Color.accentViolet)
                Text("Aucun cours à venir").font(.headline)
            }
        }
    }

    #if os(iOS)
    // MARK: Écran verrouillé (iPhone)

    private func accessoryRect(_ c: Course) -> some View {
        let ongoing = entry.current != nil
        return VStack(alignment: .leading, spacing: 1) {
            Text(ongoing ? "EN COURS" : (c.isExam ? "EXAMEN" : "PROCHAIN COURS")).font(.caption2.bold())
            Text(c.title).font(.headline).lineLimit(1)
            HStack(spacing: 4) {
                if ongoing {
                    Text("reste")
                    Text(timerInterval: c.start...c.end, countsDown: true).monospacedDigit()
                } else {
                    let rel = Fmt.relativeDay(c.start, now: entry.date)
                    Text("\(rel.isEmpty ? "à" : rel) \(Fmt.time(c.start))")
                    if !c.displayLocation.isEmpty { Text("· \(c.displayLocation)").lineLimit(1) }
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accessoryInline(_ c: Course) -> some View {
        let ongoing = entry.current != nil
        let rel = Fmt.relativeDay(c.start, now: entry.date)
        return Text(ongoing ? "\(c.title) · fin \(Fmt.time(c.end))" : "\(c.title) · \(rel.isEmpty ? "" : rel + " ")\(Fmt.time(c.start))")
    }

    private func accessoryCircle(_ c: Course) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.current != nil {
                ProgressView(timerInterval: c.start...c.end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Text(Fmt.time(c.end)).font(.system(size: 11, weight: .bold))
                }
                .progressViewStyle(.circular)
            } else {
                VStack(spacing: 0) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(Fmt.time(c.start)).font(.system(size: 12, weight: .bold))
                }
            }
        }
    }
    #endif

    private func label(_ course: Course) -> some View {
        Text(entry.current != nil ? "🔴 EN COURS" : (course.isExam ? "📝 EXAMEN" : "PROCHAIN COURS"))
            .font(.caption2.bold())
            .foregroundStyle(entry.current != nil ? Color.red : Color.accentViolet)
    }

    private func small(_ c: Course) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                label(c)
                Text(c.title).font(.headline).lineLimit(2)
                if !c.displayLocation.isEmpty {
                    Text("📍 \(c.displayLocation)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    WhenView(entry: entry, course: c, big: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ c: Course) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                label(c)
                Text(c.title).font(.headline).lineLimit(2)
                Text(["\(Fmt.time(c.start)) – \(Fmt.time(c.end))", c.displayLocation.isEmpty ? "" : "📍 \(c.displayLocation)"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let after = entry.laterToday.first {
                    Text("Puis : \(after.title) à \(Fmt.time(after.start))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            WhenView(entry: entry, course: c, big: true)
        }
    }

    private func large(_ c: Course) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            medium(c)
                .frame(height: 90)
            Divider()
            if entry.laterToday.isEmpty {
                Text("Rien d'autre ce jour-là").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Ensuite").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(entry.laterToday) { l in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(l.color).frame(width: 4, height: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(l.title).font(.callout.weight(.semibold)).lineLimit(1)
                            Text("\(Fmt.time(l.start)) – \(Fmt.time(l.end))\(l.displayLocation.isEmpty ? "" : " · \(l.displayLocation)")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if l.isExam { Text("📝").font(.caption) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Déclaration du widget

struct NextCourseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextCourse", provider: Provider()) { entry in
            EpiValastorWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Prochain cours")
        .description("Le cours en cours ou le prochain, la salle et le temps restant.")
        .supportedFamilies(families)
    }

    private var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        #else
        return [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

@main
struct EpiValastorWidgets: WidgetBundle {
    var body: some Widget {
        NextCourseWidget()
        #if os(iOS)
        CourseLiveActivity()
        #endif
    }
}
