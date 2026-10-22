import SwiftUI

/// Réglages (⌘,) : plusieurs onglets, comme sur Android.
struct SettingsView: View {
    var body: some View {
        TabView {
            CalendarsSettings().tabItem { Label("Agendas", systemImage: "calendar") }
            AppearanceSettings().tabItem { Label("Apparence", systemImage: "paintpalette") }
            HiddenSubjectsSettings().tabItem { Label("Matières masquées", systemImage: "eye.slash") }
            SyncSettings().tabItem { Label("Synchronisation", systemImage: "arrow.triangle.2.circlepath") }
            AboutSettings().tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - Agendas

private struct CalendarsSettings: View {
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
                HStack(spacing: 10) {
                    Text("Couleur")
                    Spacer()
                    ForEach(agendaPalette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: colorHex == hex ? 2.5 : 0))
                            .onTapGesture { colorHex = hex }
                    }
                }
                HStack {
                    if editing != nil {
                        Button("Annuler") { reset() }
                    }
                    Spacer()
                    Button(editing == nil ? "Ajouter le lien" : "Enregistrer") {
                        if let link = editing {
                            store.updateLink(link, url: url, name: name, colorHex: colorHex)
                        } else {
                            store.addLink(url: url, name: name, colorHex: colorHex)
                        }
                        reset()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
                        Spacer()
                        Button { edit(link) } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                        Button(role: .destructive) { store.removeLink(link) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func edit(_ link: IcsLink) {
        editing = link
        name = link.name
        url = link.url
        colorHex = link.colorHex
    }

    private func reset() {
        editing = nil
        name = ""
        url = ""
        colorHex = agendaPalette[0]
    }
}

// MARK: - Apparence

private struct AppearanceSettings: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("viewMode") private var viewMode = "week"
    @AppStorage("showNextBanner") private var showNextBanner = true
    @AppStorage("menuBarStyle") private var menuBarStyle = "full"

    var body: some View {
        Form {
            Picker("Thème", selection: $theme) {
                Text("Système").tag("system")
                Text("Clair").tag("light")
                Text("Sombre").tag("dark")
            }
            .pickerStyle(.radioGroup)
            .onChange(of: theme) { _, newValue in applyTheme(newValue) }

            Picker("Vue par défaut", selection: $viewMode) {
                Text("Semaine (un bloc par jour)").tag("week")
                Text("Jour").tag("day")
            }
            .pickerStyle(.radioGroup)

            Toggle("Pastille « prochain cours » en bas du planning", isOn: $showNextBanner)

            Picker("Barre des menus", selection: $menuBarStyle) {
                Text("Cours + temps restant").tag("full")
                Text("Temps restant seulement").tag("compact")
                Text("Icône seulement").tag("icon")
            }
            .pickerStyle(.radioGroup)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Matières masquées

private struct HiddenSubjectsSettings: View {
    @EnvironmentObject private var store: ScheduleStore

    var body: some View {
        let hidden = store.data.hiddenSubjects.sorted()
        Form {
            if hidden.isEmpty {
                Text("Aucune matière masquée.\nClique sur un cours puis « Cacher cette matière ».")
                    .foregroundStyle(.secondary)
            }
            ForEach(hidden, id: \.self) { subject in
                HStack {
                    Text(subject)
                    Spacer()
                    Button("Réafficher") { store.unhideSubject(subject) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Synchronisation

private struct SyncSettings: View {
    @EnvironmentObject private var store: ScheduleStore

    var body: some View {
        Form {
            LabeledContent("Dernière synchronisation", value: store.data.lastSync.map { Fmt.full($0) } ?? "jamais")
            LabeledContent("Automatique", value: "Au lancement, puis toutes les heures")
            Text("L'app reste active dans la barre des menus même quand la fenêtre est fermée.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button {
                    Task { await store.sync() }
                } label: {
                    if store.isSyncing { ProgressView().controlSize(.small) } else { Text("Synchroniser maintenant") }
                }
                .disabled(store.isSyncing)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - À propos

private struct AboutSettings: View {
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
    }
}
