import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// Fond des blocs de jour (clair / sombre selon le système)
    static var cardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

/// Demande « centrer ce jour à l'écran » (bouton Aujourd'hui, mini-calendrier, lancement).
struct CenterRequest: Equatable {
    let day: Date
    let nonce = UUID()
}

func weekStart(_ date: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    cal.timeZone = .current
    return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
}

// MARK: - Vue semaine

/// Une semaine : un bloc par jour, côte à côte si la fenêtre est large, l'un sous l'autre sinon.
struct WeekView: View {
    @EnvironmentObject private var store: ScheduleStore
    let anchor: Date
    @Binding var centerRequest: CenterRequest?
    let onSelect: (Course) -> Void

    var body: some View {
        let monday = weekStart(anchor)
        let sunday = Calendar.current.date(byAdding: .day, value: 7, to: monday)!
        let weekCourses = store.visible.filter { $0.start >= monday && $0.start < sunday }
        let byDay = Dictionary(grouping: weekCourses, by: \.day)
        let days = byDay.keys.sorted()

        ScrollViewReader { proxy in
            ScrollView {
                if days.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sun.max").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Aucun cours cette semaine").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                        ForEach(days, id: \.self) { day in
                            DayBlockView(day: day, courses: byDay[day] ?? [], onSelect: onSelect)
                                .id(day)
                        }
                    }
                    .padding(gridPadding)
                }
            }
            .onAppear { center(proxy, days: days) }
            .onChange(of: centerRequest) { _, _ in center(proxy, days: days) }
            .onChange(of: days) { _, newDays in center(proxy, days: newDays) }
        }
    }

    private var gridPadding: CGFloat {
        #if os(iOS)
        return 12
        #else
        return 20
        #endif
    }

    /// Centre le jour demandé (ou le prochain jour de cours de la semaine).
    private func center(_ proxy: ScrollViewProxy, days: [Date]) {
        guard let req = centerRequest, !days.isEmpty else { return }
        guard let target = days.first(where: { $0 >= req.day }) ?? days.last else { return }
        let monday = weekStart(anchor)
        guard req.day >= monday, req.day < Calendar.current.date(byAdding: .day, value: 7, to: monday)! else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut) { proxy.scrollTo(target, anchor: .center) }
        }
        centerRequest = nil
    }
}

// MARK: - Vue jour

struct DayView: View {
    @EnvironmentObject private var store: ScheduleStore
    let day: Date
    let onSelect: (Course) -> Void

    var body: some View {
        let courses = store.visible.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
        ScrollView {
            if courses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sun.max").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Aucun cours ce jour-là").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                DayBlockView(day: day, courses: courses, onSelect: onSelect)
                    .frame(maxWidth: 720)
                    .padding(20)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Bloc d'une journée

struct DayBlockView: View {
    @EnvironmentObject private var store: ScheduleStore
    let day: Date
    let courses: [Course]
    let onSelect: (Course) -> Void

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let isPast = day < Calendar.current.startOfDay(for: store.now)
        let holidays = courses.filter(\.isHoliday)
        let real = courses.filter { !$0.isHoliday }

        VStack(alignment: .leading, spacing: 0) {
            // En-tête : jour, horaires début – fin, pastilles
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Fmt.dayLong(day).components(separatedBy: " ").first ?? "")
                            .font(.headline)
                            .foregroundStyle(isToday ? Color.accentViolet : .primary)
                        if let first = real.map(\.start).min(), let last = real.map(\.end).max() {
                            Text("·  \(Fmt.time(first)) – \(Fmt.time(last))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(Fmt.dayLong(day).components(separatedBy: " ").dropFirst().joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isToday { Chip(text: "Aujourd'hui", color: .accentViolet) }
                if let h = holidays.first { Chip(text: h.holidayLabel, color: .holidayTeal) }
                if real.contains(where: \.isExam) { Chip(text: "📝 Examen", color: .examRed) }
                if !real.isEmpty {
                    Text("\(real.count) cours").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isToday ? Color.accentViolet.opacity(0.18) : (holidays.isEmpty ? Color.primary.opacity(0.05) : Color.holidayTeal.opacity(0.16)))

            VStack(spacing: 6) {
                ForEach(holidays) { h in CourseCardView(course: h).onTapGesture { onSelect(h) } }
                ForEach(dayItems(real)) { item in
                    switch item {
                    case .course(let c):
                        CourseCardView(course: c).onTapGesture { onSelect(c) }
                    case .pause(_, let label):
                        HStack {
                            Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
                            Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.cardBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isToday ? Color.accentViolet : Color.primary.opacity(0.1), lineWidth: isToday ? 2 : 1))
        .opacity(isPast ? 0.55 : 1)
    }
}

struct Chip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
}

// MARK: - Carte d'un cours

struct CourseCardView: View {
    @EnvironmentObject private var store: ScheduleStore
    let course: Course
    @State private var hovering = false

    var body: some View {
        let now = store.now
        let ongoing = !course.isHoliday && course.isOngoing(at: now)
        let color = course.color
        let strong = ongoing || course.isExam || course.isHoliday

        HStack(spacing: 0) {
            // Colonne horaires
            VStack(spacing: 2) {
                if course.isHoliday && course.isAllDay {
                    Text("Toute la").font(.caption2)
                    Text("journée").font(.caption.bold())
                } else {
                    Text(Fmt.time(course.start)).font(.system(size: 13, weight: .bold))
                    Text(Fmt.time(course.end)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 66)
            .frame(maxHeight: .infinity)
            .background(color.opacity(0.15))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(course.title).font(.system(size: 14, weight: .bold)).lineLimit(2)
                    Spacer(minLength: 6)
                    if course.isHoliday { Chip(text: course.holidayLabel, color: .holidayTeal) }
                    if course.isExam && !ongoing { Chip(text: "📝 Examen", color: .examRed) }
                    if ongoing { Chip(text: "🔴 \(Fmt.remaining(course.end.timeIntervalSince(now)))", color: .red) }
                }
                let info = [course.displayLocation.isEmpty ? nil : "📍 \(course.displayLocation)",
                            course.teacher.isEmpty ? nil : "👤 \(course.teacher)"].compactMap { $0 }
                if !info.isEmpty {
                    Text(info.joined(separator: "   ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(color.opacity(hovering ? 0.22 : 0.14))
        .overlay {
            // Ligne rouge de progression pendant le cours
            if let p = course.isHoliday ? nil : course.progress(at: now) {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color.red.opacity(0.7)).frame(height: 2).offset(y: geo.size.height * p - 1)
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -4, y: geo.size.height * p - 4)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ongoing ? Color.red : color.opacity(strong ? 1 : 0.5), lineWidth: strong ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
    }
}

// MARK: - Pastille « prochain cours »

struct NextCourseBanner: View {
    @EnvironmentObject private var store: ScheduleStore
    let onSelect: (Course) -> Void

    var body: some View {
        let now = store.now
        let pair = currentAndNext(store.visible, at: now)
        let current = pair.current
        if let shown = pair.current ?? pair.next {
            let label: String = {
                if current != nil { return "🔴 En cours · reste \(Fmt.remaining(shown.end.timeIntervalSince(now)))" }
                let secs = shown.start.timeIntervalSince(now)
                if secs <= 12 * 3600 { return "⏳ Dans \(Fmt.remaining(secs))" }
                let rel = Fmt.relativeDay(shown.start, now: now)
                return "📅 \(rel.isEmpty ? "" : rel.capitalizedFirst + " ")à \(Fmt.time(shown.start))"
            }()
            Button { onSelect(shown) } label: {
                VStack(spacing: 1) {
                    Text(label).font(.caption.bold()).foregroundStyle(current != nil ? Color.red : Color.accentViolet)
                    Text((shown.isExam ? "📝 " : "") + shown.title + (shown.displayLocation.isEmpty ? "" : " · 📍 \(shown.displayLocation)"))
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(shown.color, lineWidth: 1.5))
                .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 520)
        }
    }
}
