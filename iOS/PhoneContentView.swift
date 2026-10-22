import SwiftUI

/// Écran principal sur iPhone / iPad : planning semaine ou jour, comme sur Android.
struct PhoneContentView: View {
    @EnvironmentObject private var store: ScheduleStore
    @AppStorage("viewMode") private var viewMode = "week"
    @AppStorage("showNextBanner") private var showNextBanner = true

    @State private var anchor = Calendar.current.startOfDay(for: Date())
    @State private var searchText = ""
    @State private var selected: Course?
    @State private var showStats = false
    @State private var showChanges = false
    @State private var showCalendar = false
    @State private var showSettings = false
    @State private var centerRequest: CenterRequest? = CenterRequest(day: Calendar.current.startOfDay(for: Date()))

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.isEmpty {
                    SearchResultsView(query: searchText) { course in
                        searchText = ""
                        jump(to: course.day)
                        selected = course
                    }
                } else if store.data.links.isEmpty {
                    emptyState
                } else if viewMode == "week" {
                    WeekView(anchor: anchor, centerRequest: $centerRequest) { selected = $0 }
                } else {
                    DayView(day: anchor) { selected = $0 }
                }
            }
            // Balayer à gauche / à droite pour changer de semaine ou de jour
            .gesture(
                DragGesture(minimumDistance: 40).onEnded { value in
                    guard searchText.isEmpty, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    move(value.translation.width < 0 ? 1 : -1)
                }
            )
            .refreshable { await store.sync() }
            .safeAreaInset(edge: .bottom) {
                if showNextBanner && searchText.isEmpty && !store.data.links.isEmpty {
                    NextCourseBanner { selected = $0 }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Matière, prof ou salle")
            .toolbar { toolbar }
            .sheet(item: $selected) { course in
                CourseDetailView(course: course).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showStats) { StatsView() }
            .sheet(isPresented: $showChanges) {
                ChangesView { course in
                    showChanges = false
                    jump(to: course.day)
                    selected = course
                }
            }
            .sheet(isPresented: $showCalendar) {
                MiniCalendarView(selected: anchor) { day in
                    showCalendar = false
                    jump(to: day)
                }
                .presentationDetents([.height(380)])
            }
            .sheet(isPresented: $showSettings) { PhoneSettingsView() }
            .alert("Synchronisation", isPresented: Binding(get: { store.syncError != nil }, set: { if !$0 { store.syncError = nil } })) {
                Button("OK") { store.syncError = nil }
            } message: {
                Text(store.syncError ?? "")
            }
            // Ouverture depuis la notification « changements »
            .onReceive(NotificationCenter.default.publisher(for: .openChanges)) { _ in showChanges = true }
        }
    }

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
        withAnimation { anchor = Calendar.current.date(byAdding: .day, value: direction * step, to: anchor) ?? anchor }
    }

    private func jump(to day: Date) {
        anchor = day
        centerRequest = CenterRequest(day: day)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Vue", selection: $viewMode) {
                    Label("Semaine", systemImage: "calendar.day.timeline.left").tag("week")
                    Label("Jour", systemImage: "calendar").tag("day")
                }
                Divider()
                Button { showCalendar = true } label: { Label("Mini-calendrier", systemImage: "calendar") }
                Button { showStats = true } label: { Label("Statistiques", systemImage: "chart.bar") }
                Button { Task { await store.sync() } } label: { Label("Synchroniser", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "line.3.horizontal")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showChanges = true } label: {
                Image(systemName: "bell")
                    .overlay(alignment: .topTrailing) {
                        if store.unseenChangesCount > 0 {
                            Text("\(min(store.unseenChangesCount, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(.red))
                                .offset(x: 9, y: -7)
                        }
                    }
            }
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Button("Aujourd'hui") { jump(to: Calendar.current.startOfDay(for: Date())) }
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentViolet)
            Text("Aucun agenda pour le moment").font(.title3.bold())
            Text("Ajoute le lien ICS de ton emploi du temps (Zeus…) dans les réglages.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Ajouter un lien ICS") { showSettings = true }
                .buttonStyle(.borderedProminent)
                .tint(.accentViolet)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let openChanges = Notification.Name("EpiValastorOpenChanges")
}
