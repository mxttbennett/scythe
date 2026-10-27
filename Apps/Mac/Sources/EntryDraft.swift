import Foundation
import ScytheCore

enum EntryAction: Equatable {
    case log(hours: Double)
    case startTimer

    var hours: Double? {
        if case .log(let hours) = self { return hours }
        return nil
    }
}

struct EntryDraft {
    var target: TimerTarget
    var date: CalendarDate
    var action: EntryAction
    var notes: String?

    /// Nil when not sendable: bad or zero hours, or blank hours on a day other than today, since a timer only runs now.
    static func action(
        hoursText: String,
        date: CalendarDate,
        today: CalendarDate = .today(),
        locale: Locale = .autoupdatingCurrent
    ) -> EntryAction? {
        let trimmed = hoursText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return date == today ? .startTimer : nil }
        guard let hours = Double.hours(parsing: trimmed, locale: locale), hours > 0 else { return nil }
        return .log(hours: hours)
    }
}
