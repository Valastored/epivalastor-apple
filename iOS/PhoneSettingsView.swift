import SwiftUI
import ActivityKit

/// Réglages sur iPhone : une liste de pages, comme sur Android.
struct PhoneSettingsView: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = "system"
    @AppStorage("viewMode") private var viewMode = "week"

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { AppearancePage() } label: {
                    row("Apparence", "paintpalette", "Thème \(theme == "dark" ? "sombre" : theme == "light" ? "clair" : "système") · vue \(viewMode == "week" ? "semaine" : "jour")")
                }
                NavigationLink { CalendarsPage() } label: {
                    row("Agendas", "calendar", store.data.links.isEmpty ? "Aucun agenda ICS" : "\(store.data.links.count) agenda\(store.data.links.count > 1 ? "s" : "") ICS")
                }
                NavigationLink { NotificationsPage() } label: {
                    row("Notifications", "bell", "Rappels, examens, changements, Live Activity")
                }
                NavigationLink { HiddenPage() } label: {
                    row("Matières masquées", "eye.slash", store.data.hiddenSubjects.isEmpty ? "Aucune" : "\(store.data.hiddenSubjects.count)")
                }
                NavigationLink { SyncPage() } label: {
                    row("Synchronisation", "arrow.triangle.2.circlepath", "À l'ouverture et chaque jour vers 6 h")
                }
                NavigationLink { AboutPage() } label: {
                    row("À propos", "info.circle", "EpiValastor, par Valastor")
                }
            }
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func row(_ title: String, _ icon: String, _ subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.accentViolet)
        }
    }
}

// MARK: - Pages

private struct AppearancePage: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("viewMode") private var viewMode = "week"
    @AppStorage("showNextBanner") private var showNextBanner = true

    var body: some View {
        Form {
            Section("Thème") {
                Picker("Thème", selection: $theme) {
                    Text("Système").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Planning") {
                Picker("Vue", selection: $viewMode) {
                    Text("Semaine (un bloc par jour)").tag("week")
                    Text("Jour").tag("day")
                }
                Toggle("Pastille « prochain cours »", isOn: $showNextBanner)
            }
        }
        .navigationTitle("Apparence")
    }
}

private struct CalendarsPage: View {
    @EnvironmentObject private var store: ScheduleStore
    @State private var name = ""
    @State private var url = ""
    @State private var colorHex = agendaPalette[0]
    @State private var editing: IcsLink?

    var body: some View {
        Form {
            Section(editing == nil ? "Ajouter un agenda" : "Modifier l'agenda") {
                TextField("Nom (ex : EPITA, GDG)", text: $name)
                TextField("Lien ICS", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    ForEach(agendaPalette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: colorHex == hex ? 3 : 0))
                            .onTapGesture { colorHex = hex }
                        if hex != agendaPalette.last { Spacer() }
                    }
                }
                .padding(.vertical, 4)
                Button(editing == nil ? "Ajouter le lien" : "Enregistrer") {
                    if let link = editing {
                        store.updateLink(link, url: url, name: name, colorHex: colorHex)
                    } else {
                        store.addLink(url: url, name: name, colorHex: colorHex)
                    }
                    reset()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty)
                if editing != nil { Button("Annuler", role: .cancel) { reset() } }
            }

            Section("Agendas actifs") {
                if store.data.links.isEmpty {
                    Text("Aucun agenda pour le moment.").foregroundStyle(.secondary)
                }
                ForEach(store.data.links) { link in
                    HStack {
                        Circle().fill(Color(hex: link.colorHex)).frame(width: 12, height: 12)
                        VStack(alignment: .leading) {
                            Text(link.name).bold()
                            Text(link.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { edit(link) }
                    .swipeActions {
                        Button(role: .destructive) { store.removeLink(link) } label: { Label("Supprimer", systemImage: "trash") }
                        Button { edit(link) } label: { Label("Modifier", systemImage: "pencil") }.tint(.accentViolet)
                    }
                }
            }
        }
        .navigationTitle("Agendas")
    }

    private func edit(_ link: IcsLink) {
        editing = link; name = link.name; url = link.url; colorHex = link.colorHex
    }

    private func reset() {
        editing = nil; name = ""; url = ""; colorHex = agendaPalette[0]
    }
}

private struct NotificationsPage: View {
    @EnvironmentObject private var store: ScheduleStore
    @AppStorage("remindersOn") private var remindersOn = true
    @AppStorage("reminderMinutes") private var reminderMinutes = 15
    @AppStorage("examNotifOn") private var examNotifOn = true
    @AppStorage("changeNotifOn") private var changeNotifOn = true
    @AppStorage("liveActivityOn") private var liveActivityOn = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle("Live Activity", isOn: $liveActivityOn)
            } header: {
                Text("Pendant un cours")
            } footer: {
                Text(ActivityAuthorizationInfo().areActivitiesEnabled
                     ? "Le cours en cours (ou celui qui commence dans l'heure) reste affiché sur l'écran verrouillé et dans la Dynamic Island, avec le temps restant."
                     : "Les Live Activities sont désactivées pour EpiValastor dans les réglages de l'iPhone.")
            }
            Section("Avant un cours") {
                Toggle("Rappel avant le cours", isOn: $remindersOn)
                Picker("Délai", selection: $reminderMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { m in Text(m == 60 ? "1 h" : "\(m) min").tag(m) }
                }
                .pickerStyle(.segmented)
                .disabled(!remindersOn)
            }
            Section("Examens") {
                Toggle("Rappel la veille à 19 h", isOn: $examNotifOn)
            }
            Section("Emploi du temps") {
                Toggle("Changements (ajouts, annulations, déplacements)", isOn: $changeNotifOn)
            }
            Section {
                Button("Réglages des notifications de l'iPhone") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
        }
        .navigationTitle("Notifications")
        .onChange(of: remindersOn) { _, _ in PhoneServices.refresh(store) }
        .onChange(of: reminderMinutes) { _, _ in PhoneServices.refresh(store) }
        .onChange(of: examNotifOn) { _, _ in PhoneServices.refresh(store) }
        .onChange(of: liveActivityOn) { _, _ in PhoneServices.refresh(store) }
    }
}

private struct HiddenPage: View {
    @EnvironmentObject private var store: ScheduleStore

    var body: some View {
        List {
            if store.data.hiddenSubjects.isEmpty {
                Text("Aucune matière masquée.\nTouche un cours puis « Cacher cette matière ».")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.data.hiddenSubjects.sorted(), id: \.self) { subject in
                HStack {
                    Text(subject)
                    Spacer()
                    Button("Réafficher") { store.unhideSubject(subject) }
                }
            }
        }
        .navigationTitle("Matières masquées")
    }
}

private struct SyncPage: View {
    @EnvironmentObject private var store: ScheduleStore

    var body: some View {
        Form {
            LabeledContent("Dernière synchro", value: store.data.lastSync.map { Fmt.full($0) } ?? "jamais")
            Section {
                Text("À chaque ouverture de l'app, toutes les heures quand elle est ouverte, et chaque jour vers 6 h en arrière-plan (iOS choisit le moment exact).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.sync() }
            } label: {
                HStack {
                    Text("Synchroniser maintenant")
                    if store.isSyncing { Spacer(); ProgressView() }
                }
            }
            .disabled(store.isSyncing)
        }
        .navigationTitle("Synchronisation")
    }
}

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentViolet)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.accentViolet.opacity(0.15)))
            Text("EpiValastor").font(.title.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .foregroundStyle(.secondary)
            Text("Développé par Valastor").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("À propos")
    }
}
