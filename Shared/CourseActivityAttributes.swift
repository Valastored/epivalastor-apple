#if os(iOS)
import Foundation
import ActivityKit

/// Données d'une Live Activity (cours en cours / imminent), affichée sur l'écran verrouillé et dans la Dynamic Island.
struct CourseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var location: String
        var start: Date
        var end: Date
        var ongoing: Bool
        var colorHex: String
        var isExam: Bool
    }

    var calendarName: String
}
#endif
