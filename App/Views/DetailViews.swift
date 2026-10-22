import SwiftUI

// MARK: - Détails d'un cours

struct CourseDetailView: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    let course: Course

    var body: some View {
        let now = store.now
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(course.title).font(.title2.bold())
                Spacer()
                if course.isHoliday { Chip(text: course.holidayLabel, color: .holidayTeal) }
                if course.isExam { Chip(text: "📝 Examen", color: .examRed) }
            }

            // Chaque agenda dans sa propre couleur (« EPITA & GDG »)
            let names = course.calendarName.components(separatedBy: " & ")
            names.enumerated().reduce(Text(names.count > 1 ? "Agendas : " : "Agenda : ").bold()) { acc, pair in
                let sep = pair.offset > 0 ? Text(" & ") : Text("")
                let name = Text(pair.element).bold().foregroundColor(store.color(ofCalendar: pair.element) ?? course.color)
                return acc + sep + name
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.dayLong(course.start)).font(.headline)
                Text(course.isHoliday && course.isAllDay ? "Toute la journée" : "\(Fmt.time(course.start)) – \(Fmt.time(course.end)) · \(Fmt.minutes(course.minutes))")
                if course.isOngoing(at: now) && !course.isHoliday {
                    Text("🔴 En cours · reste \(Fmt.remaining(course.end.timeIntervalSince(now)))").foregroundStyle(.red).bold()
                } else if course.start > now && course.start.timeIntervalSince(now) < 24 * 3600 {
                    Text("⏳ Commence dans \(Fmt.remaining(course.start.timeIntervalSince(now)))").bold()
                }
            }

            if !course.displayLocation.isEmpty {
                LabeledContent("Salle") { Text(course.displayLocation).textSelection(.enabled) }
            }
            if !course.teacher.isEmpty {
                LabeledContent("Prof") { Text(course.teacher) }
            }
            if !course.details.isEmpty {
                Text("Description").font(.headline)
                ScrollView {
                    Text(course.details).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            HStack {
                Button("Cacher cette matière", role: .destructive) {
                    store.hideSubject(course.title)
                    dismiss()
                }
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 460)
        #endif
    }
}

// MARK: - Changements récents

struct ChangesView: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    let onOpenCourse: (Course) -> Void
    @State private var unseenAtOpen: Set<UUID> = []

    /// Un même cours présent dans deux agendas n'apparaît qu'une fois
    private var changes: [ScheduleChange] {
        var seenKeys = Set<String>()
        return store.data.changes.filter { c in
            let key = "\(c.type)|\(c.title)|\(c.oldStart?.timeIntervalSince1970 ?? 0)|\(c.newStart?.timeIntervalSince1970 ?? 0)"
            return seenKeys.insert(key).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("🔔 Changements récents").font(.title3.bold())
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            if changes.isEmpty {
                Text("Aucun changement détecté sur les 14 prochains jours.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(changes) { change in
                    ChangeRow(change: change, isNew: unseenAtOpen.contains(change.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard change.type != .removed, let start = change.newStart,
                                  let course = store.visible.first(where: { $0.title == change.title && $0.start == start })
                            else { return }
                            onOpenCourse(course)
                        }
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 520)
        #endif
        .onAppear {
            unseenAtOpen = Set(store.data.changes.filter { !$0.seen }.map(\.id))
            store.markChangesSeen()
        }
    }
}

private struct ChangeRow: View {
    let change: ScheduleChange
    let isNew: Bool

    private var label: String {
        switch change.type {
        case .added: return "🆕 Ajouté"
        case .removed: return "❌ Annulé"
        case .modified: return "✏️ Modifié"
        }
    }

    private var color: Color {
        switch change.type {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: change.colorHex)).frame(width: 9, height: 9)
                Text(label).font(.caption.bold()).foregroundStyle(color)
                if isNew { Text("• nouveau").font(.caption.bold()).foregroundStyle(Color.accentViolet) }
            }
            Text(change.title).font(.headline).strikethrough(change.type == .removed)
            if let old = change.oldTitle { Text("Ancien nom : \(old)").font(.caption) }
            switch change.type {
            case .added:
                Text("📅 \(when(change.newStart, change.newEnd)) · 📍 \(change.newLocation ?? "")").font(.caption)
            case .removed:
                Text("📅 \(when(change.oldStart, change.oldEnd)) · 📍 \(change.oldLocation ?? "")").font(.caption).strikethrough()
            case .modified:
                if change.oldStart != change.newStart || change.oldEnd != change.newEnd {
                    Text("📅 \(when(change.oldStart, change.oldEnd))").font(.caption).strikethrough()
                    Text("➡️ \(when(change.newStart, change.newEnd))").font(.caption.bold())
                } else {
                    Text("📅 \(when(change.newStart, change.newEnd))").font(.caption)
                }
                if change.oldLocation != change.newLocation {
                    Text("📍 \(change.oldLocation ?? "?") ➡️ \(change.newLocation ?? "?")").font(.caption.bold())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func when(_ s: Date?, _ e: Date?) -> String {
        guard let s else { return "?" }
        return "\(Fmt.dayShort(s)) \(Fmt.time(s))" + (e.map { " – \(Fmt.time($0))" } ?? "")
    }
}

// MARK: - Mini-calendrier

struct MiniCalendarView: View {
    @EnvironmentObject private var store: ScheduleStore
    let selected: Date
    let onSelect: (Date) -> Void
    @State private var month: Date = Date()

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        let byDay = Dictionary(grouping: store.visible, by: \.day)
        let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)!.count
        let offset = (cal.component(.weekday, from: firstOfMonth) + 5) % 7 // lundi = 0
        let cells = offset + daysInMonth
        let rows = (cells + 6) / 7

        VStack(spacing: 8) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(Fmt.month(firstOfMonth)).font(.headline)
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)

            HStack(spacing: 0) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "J", "V", "S", "D"][i]).font(.caption).foregroundStyle(.secondary).frame(width: 34)
                }
            }

            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let n = row * 7 + col - offset + 1
                        if n >= 1 && n <= daysInMonth, let date = cal.date(byAdding: .day, value: n - 1, to: firstOfMonth) {
                            dayCell(date: date, number: n, courses: byDay[date] ?? [])
                        } else {
                            Color.clear.frame(width: 34, height: 34)
                        }
                    }
                }
            }

            HStack {
                Button("Aujourd'hui") { onSelect(Calendar.current.startOfDay(for: Date())) }
                Spacer()
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 270)
        .onAppear { month = selected }
    }

    private func dayCell(date: Date, number: Int, courses: [Course]) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let hasExam = courses.contains(where: \.isExam)
        let holidayOnly = !courses.isEmpty && courses.allSatisfy(\.isHoliday)
        let colors = Array(Set(courses.filter { !$0.isHoliday }.map(\.colorHex))).sorted().prefix(3)

        return Button { onSelect(date) } label: {
            VStack(spacing: 2) {
                Text("\(number)")
                    .font(.system(size: 12, weight: courses.isEmpty ? .regular : .bold))
                    .foregroundStyle(courses.isEmpty ? .secondary : .primary)
                HStack(spacing: 2) {
                    if hasExam {
                        Circle().fill(Color.examRed).frame(width: 5, height: 5)
                    } else if holidayOnly {
                        Circle().fill(Color.holidayTeal).frame(width: 5, height: 5)
                    } else {
                        ForEach(Array(colors), id: \.self) { hex in Circle().fill(Color(hex: hex)).frame(width: 5, height: 5) }
                    }
                }
                .frame(height: 5)
            }
            .frame(width: 32, height: 32)
            .background(Circle().fill(holidayOnly ? Color.holidayTeal.opacity(0.2) : (courses.isEmpty ? Color.clear : Color.accentViolet.opacity(0.1))))
            .overlay(Circle().strokeBorder(isToday ? Color.accentViolet : .clear, lineWidth: 2))
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
