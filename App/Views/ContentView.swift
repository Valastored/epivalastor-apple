import SwiftUI

/// Fenêtre principale : planning semaine / jour, recherche, mini-calendrier, statistiques, changements.
struct ContentView: View {
    @EnvironmentObject private var store: ScheduleStore
    @AppStorage("viewMode") private var viewMode = "week"
    @AppStorage("showNextBanner") private var showNextBanner = true

    @State private var anchor = Calendar.current.startOfDay(for: Date())
    @State private var searchText = ""
    @State private var selected: Course?
    @State private var showStats = false
    @State private var showChanges = false
    @State private var showCalendar = false
    @State private var centerRequest: CenterRequest? = CenterRequest(day: Calendar.current.startOfDay(for: Date()))

    var body: some View {
        Group {
            if !searchText.isEmpty {
                SearchResultsView(query: searchText) { course in
                    jump(to: course.day)
                    searchText = ""
                    selected = course
                }
            } else if store.data.links.isEmpty {
                EmptyStateView()
            } else if viewMode == "week" {
                WeekView(anchor: anchor, centerRequest: $centerRequest) { selected = $0 }
            } else {
                DayView(day: anchor) { selected = $0 }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showNextBanner && searchText.isEmpty {
                NextCourseBanner { selected = $0 }
                    .padding(.bottom, 10)
            }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Matière, prof ou salle")
        .toolbar { toolbar }
        .sheet(item: $selected) { CourseDetailView(course: $0) }
        .sheet(isPresented: $showStats) { StatsView() }
        .sheet(isPresented: $showChanges) { ChangesView { course in showChanges = false; jump(to: course.day); selected = course } }
        .alert("Synchronisation", isPresented: Binding(get: { store.syncError != nil }, set: { if !$0 { store.syncError = nil } })) {
            Button("OK") { store.syncError = nil }
        } message: {
            Text(store.syncError ?? "")
        }
    }

    // MARK: - Navigation

    private var title: String {
        if viewMode == "week" {
            let monday = weekStart(anchor)
            let sunday = Calendar.current.date(byAdding: .day, value: 6, to: monday)!
            return "Semaine du \(Fmt.dayNum(monday)) au \(Fmt.dayNum(sunday))"
        }
        return Fmt.dayLong(anchor)
    }

    private func move(_ direction: Int) {
        let step = viewMode == "week" ? 7 : 1
        anchor = Calendar.current.date(byAdding: .day, value: direction * step, to: anchor) ?? anchor
    }

    private func goToday() {
        jump(to: Calendar.current.startOfDay(for: Date()))
    }

    private func jump(to day: Date) {
        anchor = day
        centerRequest = CenterRequest(day: day)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .help(viewMode == "week" ? "Semaine précédente" : "Jour précédent")
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Aujourd'hui") { goToday() }
                .keyboardShortcut("t", modifiers: .command)
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .help(viewMode == "week" ? "Semaine suivante" : "Jour suivant")
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }

        ToolbarItem(placement: .principal) {
            Picker("Vue", selection: $viewMode) {
                Text("Semaine").tag("week")
                Text("Jour").tag("day")
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { showCalendar.toggle() } label: { Image(systemName: "calendar") }
                .help("Mini-calendrier")
                .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                    MiniCalendarView(selected: anchor) { day in
                        showCalendar = false
                        jump(to: day)
                    }
                }

            Button { showChanges = true } label: {
                Image(systemName: "bell")
                    .overlay(alignment: .topTrailing) {
                        if store.unseenChangesCount > 0 {
                            Text("\(min(store.unseenChangesCount, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(.red))
                                .offset(x: 8, y: -6)
                        }
                    }
            }
            .help("Changements récents")

            Button { showStats = true } label: { Image(systemName: "chart.bar") }
                .help("Statistiques")

            Button { Task { await store.sync() } } label: {
                if store.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("Synchroniser (⌘R)")
            .disabled(store.isSyncing)
        }
    }
}

struct EmptyStateView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentViolet)
            Text("Aucun agenda pour le moment").font(.title2.bold())
            Text("Ajoute le lien ICS de ton emploi du temps (Zeus, Hyperplanning…) dans les réglages.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Ajouter un lien ICS") { openSettings() }
                .buttonStyle(.borderedProminent)
                .tint(.accentViolet)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
