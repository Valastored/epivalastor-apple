import SwiftUI
import AppKit

@main
struct EpiValastorApp: App {
    @StateObject private var store = ScheduleStore()
    @AppStorage("theme") private var theme = "system"

    var body: some Scene {
        WindowGroup("EpiValastor", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 560, minHeight: 480)
                .onAppear { applyTheme(theme) }
                .onChange(of: theme) { _, newValue in applyTheme(newValue) }
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Synchroniser") { Task { await store.sync() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }

        // Barre des menus : prochain cours et compte à rebours toujours visibles
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Thème de toute l'app (fenêtres, réglages, barre des menus) : système, clair ou sombre.
@MainActor
func applyTheme(_ theme: String) {
    switch theme {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
}
