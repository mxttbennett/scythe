import Foundation
import ScytheCore

enum EntryTimestamp {
    /// The day is named only when the entry was logged on a different day than it is for.
    static func label(
        createdAt: Date,
        spentDate: CalendarDate,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = createdAt.formatted(style.hour().minute())
        guard CalendarDate(createdAt, in: calendar) != spentDate else { return "Created @ \(time)" }
        return "Created @ \(time) · \(createdAt.formatted(style.month(.abbreviated).day()))"
    }
}
