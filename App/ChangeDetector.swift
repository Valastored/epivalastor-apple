import Foundation

/// Compare les cours futurs avant / après une synchro (même logique que sur Android) :
/// 1. identiques (titre, horaires, salle) = inchangés ; 2. même identifiant ICS = modifié ;
/// 3. le reste = ajouté ou annulé. Seuls les changements des 14 prochains jours sont gardés.
enum ChangeDetector {
    static func detect(old: [Course], new: [Course], link: IcsLink, now: Date) -> [ScheduleChange] {
        var oldPool: [String: [Course]] = Dictionary(grouping: old, by: \.signature)
        var unmatchedNew: [Course] = []
        for n in new {
            if var list = oldPool[n.signature], !list.isEmpty {
                list.removeLast()
                oldPool[n.signature] = list
            } else {
                unmatchedNew.append(n)
            }
        }
        var unmatchedOld = oldPool.values.flatMap { $0 }

        var oldByKey: [String: [Course]] = Dictionary(grouping: unmatchedOld.filter { !$0.eventKey.isEmpty }, by: \.eventKey)
        var changes: [ScheduleChange] = []

        for n in unmatchedNew {
            if !n.eventKey.isEmpty, var list = oldByKey[n.eventKey], !list.isEmpty {
                let o = list.removeFirst()
                oldByKey[n.eventKey] = list
                if let idx = unmatchedOld.firstIndex(of: o) { unmatchedOld.remove(at: idx) }
                changes.append(ScheduleChange(
                    calendarName: link.name, colorHex: link.colorHex, type: .modified,
                    title: n.title, oldTitle: o.title != n.title ? o.title : nil,
                    oldStart: o.start, oldEnd: o.end, newStart: n.start, newEnd: n.end,
                    oldLocation: o.location, newLocation: n.location, detectedAt: now))
            } else {
                changes.append(ScheduleChange(
                    calendarName: link.name, colorHex: link.colorHex, type: .added,
                    title: n.title, newStart: n.start, newEnd: n.end, newLocation: n.location, detectedAt: now))
            }
        }
        for o in unmatchedOld {
            changes.append(ScheduleChange(
                calendarName: link.name, colorHex: link.colorHex, type: .removed,
                title: o.title, oldStart: o.start, oldEnd: o.end, oldLocation: o.location, detectedAt: now))
        }

        let horizon = now.addingTimeInterval(14 * 86400)
        return changes.filter { c in
            [c.oldStart, c.newStart].compactMap { $0 }.contains { $0 >= now && $0 <= horizon }
        }
    }
}
