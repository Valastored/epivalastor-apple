import SwiftUI
import AppKit

/// Texte affiché dans la barre des menus : cours en cours / prochain cours et temps restant.
struct MenuBarLabel: View {
    @ObservedObject var store: ScheduleStore
    @AppStorage("menuBarStyle") private var style = "full"

    var body: some View {
        let now = store.now
        let pair = currentAndNext(store.visible, at: now)
        HStack(spacing: 4) {
            Image(systemName: pair.current != nil ? "record.circle" : "calendar")
            if style != "icon", let text = labelText(pair.current, pair.next, now: now) {
                Text(text)
            }
        }
    }

    private func labelText(_ current: Course?, _ next: Course?, now: Date) -> String? {
        if let c = current {
            let left = Fmt.remaining(c.end.timeIntervalSince(now))
            return style == "compact" ? left : "\(short(c.title)) · \(left)"
        }
        guard let n = next else { return nil }
        let secs = n.start.timeIntervalSince(now)
        let when: String
        if secs <= 3 * 3600 {
            when = "dans \(Fmt.remaining(secs))"
        } else {
            let rel = Fmt.relativeDay(n.start, now: now)
            when = (rel.isEmpty ? "" : rel + " ") + Fmt.time(n.start)
        }
        return style == "compact" ? when : "\(short(n.title)) · \(when)"
    }

    private func short(_ s: String) -> String { s.count > 18 ? String(s.prefix(17)) + "…" : s }
}

/// Fenêtre qui s'ouvre en cliquant sur l'icône de la barre des menus.
struct MenuBarView: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let now = store.now
        let pair = currentAndNext(store.visible, at: now)
        let shown = pair.current ?? pair.next
        let todayRest = store.visible.filter {
            !$0.isHoliday && Calendar.current.isDateInToday($0.start) && $0.end > now && $0.id != shown?.id
        }

        VStack(alignment: .leading, spacing: 10) {
            if let c = shown {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pair.current != nil ? "🔴 EN COURS" : (c.isExam ? "📝 EXAMEN" : "PROCHAIN COURS"))
                        .font(.caption.bold())
                        .foregroundStyle(pair.current != nil ? Color.red : Color.accentViolet)
                    Text(c.title).font(.headline).lineLimit(2)
                    Text([Fmt.relativeDay(c.start, now: now).capitalizedFirst, "\(Fmt.time(c.start)) – \(Fmt.time(c.end))", c.displayLocation.isEmpty ? "" : "📍 \(c.displayLocation)"]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    // Compte à rebours en direct
                    HStack(spacing: 4) {
                        Text(pair.current != nil ? "Reste" : "Dans")
                        Text(timerInterval: now...(pair.current != nil ? c.end : max(c.start, now)), countsDown: true)
                            .monospacedDigit()
                            .bold()
                    }
                    .font(.title3)
                    if let p = c.progress(at: now) {
                        ProgressView(value: p).tint(.red)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(c.color.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.color, lineWidth: 1.5))
            } else {
                Text("Aucun cours à venir 🎉").font(.headline)
            }

            if !todayRest.isEmpty {
                Text("Plus tard aujourd'hui").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(todayRest.prefix(6)) { c in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 4, height: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.title).font(.callout.weight(.semibold)).lineLimit(1)
                            Text("\(Fmt.time(c.start)) – \(Fmt.time(c.end))\(c.displayLocation.isEmpty ? "" : " · \(c.displayLocation)")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Button("Ouvrir EpiValastor") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button { Task { await store.sync() } } label: {
                    if store.isSyncing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .help("Synchroniser")
                Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "gearshape") }
                    .help("Réglages")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quitter")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }
}
