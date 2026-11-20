import ActivityKit
import Foundation

/**
 * The next turn on the lock screen and in the Dynamic Island while a drive is on (GitHub idea, 0.7.17).
 * Shared by Kite and its widget: Kite fills it in, the widget draws it.
 */
@available(iOS 16.1, *)
struct NavActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /** The SF Symbol for the turn ("arrow.turn.up.left"). */
        var symbol: String
        /** "300 yds", already in the person's units. */
        var distance: String
        /** "Turn left", "2nd exit". */
        var instruction: String
        /** The road you turn onto, when known. */
        var road: String?
        /** "8:14 am", when you'll get there. */
        var arrival: String
        var arrived: Bool
    }

    var destination: String
}
