import Foundation
import ScytheCore

/// How the explorer writes a day in its Date column.
enum EntryDateFormat: String, CaseIterable {
    case weekdayMonthDayYear
    case monthDayYear
    case numeric
    case iso

    func formatted(_ date: CalendarDate, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let day = date.startOfDay(in: calendar)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch self {
        case .weekdayMonthDayYear:
            return day.formatted(style.weekday(.abbreviated).month(.abbreviated).day().year())
        case .monthDayYear:
            return day.formatted(style.month(.abbreviated).day().year())
        case .numeric:
            return day.formatted(
                Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            )
        case .iso:
            return day.formatted(Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day())
        }
    }
}

@MainActor
@Observable
final class EntryDateFormatPreference {
    private static let defaultsKey = "entryDateFormat"

    var format: EntryDateFormat {
        didSet {
            guard format != oldValue else { return }
            defaults.set(format.rawValue, forKey: Self.defaultsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        format = defaults.string(forKey: Self.defaultsKey).flatMap(EntryDateFormat.init(rawValue:)) ?? .weekdayMonthDayYear
    }
}
