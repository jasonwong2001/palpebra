import Foundation
import PalpebraCore

extension NextBreak {
    /// The menu bar's sentence, naming when a pause ends.
    func sentence(pausedUntil: Date?) -> String {
        guard self == .paused, let pausedUntil else { return sentence }
        return "\(sentence) until \(PauseText.end(pausedUntil))"
    }
}

enum PauseText {
    /// A time today, or a date and time after today, in the user's own time format.
    static func end(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }
}
