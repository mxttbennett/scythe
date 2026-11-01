import Foundation

/// A timezone-free calendar day, as Harvest's `spent_date` fields represent it.
///
/// Harvest returns `"2026-08-29"` with no zone. Round-tripping that through `Date`
/// means every entry is one day off for somebody, so days stay days here and only
/// become `Date` at the edges, against an explicit calendar.
public struct CalendarDate: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar` (the user's current calendar by default).
    public init(_ date: Date, in calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func today(in calendar: Calendar = .current) -> CalendarDate {
        CalendarDate(Date(), in: calendar)
    }

    /// Midnight at the start of this day.
    public func startOfDay(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    public func adding(days: Int, in calendar: Calendar = .current) -> CalendarDate {
        if isProlepticGregorian(calendar) { return CalendarDate(dayNumber: dayNumber + days) }
        let shifted = calendar.date(byAdding: .day, value: days, to: startOfDay(in: calendar))
        return CalendarDate(shifted ?? startOfDay(in: calendar), in: calendar)
    }

    /// Whole days from `other` to this date. Negative when `other` is later.
    public func daysSince(_ other: CalendarDate, in calendar: Calendar = .current) -> Int {
        if isProlepticGregorian(calendar), other.year >= Self.firstGregorianYear { return dayNumber - other.dayNumber }
        return calendar.dateComponents(
            [.day],
            from: other.startOfDay(in: calendar),
            to: startOfDay(in: calendar)
        ).day ?? 0
    }

    /// The first day of this date's week, honouring the account's `week_start_day`.
    public func startOfWeek(weekStart: Weekday, in calendar: Calendar = .current) -> CalendarDate {
        if isProlepticGregorian(calendar) {
            let offset = (weekdayIndex - (weekStart.calendarIndex - 1) + 7) % 7
            return CalendarDate(dayNumber: dayNumber - offset)
        }
        var calendar = calendar
        calendar.firstWeekday = weekStart.calendarIndex
        let interval = calendar.dateInterval(of: .weekOfYear, for: startOfDay(in: calendar))
        guard let interval else { return self }
        return CalendarDate(interval.start, in: calendar)
    }

    /// Foundation's Gregorian calendar switches from the Julian one in 1582; nothing Harvest holds is that old.
    private static let firstGregorianYear = 1583

    /// Calendar round trips cost microseconds a call, which adds up across a history of thousands of entries.
    private func isProlepticGregorian(_ calendar: Calendar) -> Bool {
        calendar.identifier == .gregorian && year >= Self.firstGregorianYear
    }

    /// Days since 1970-01-01.
    var dayNumber: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    init(dayNumber: Int) {
        let shifted = dayNumber + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        self.init(
            year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
            month: month,
            day: dayOfYear - (153 * monthIndex + 2) / 5 + 1
        )
    }

    /// 0 is Sunday. 1970-01-01 was a Thursday.
    var weekdayIndex: Int {
        ((dayNumber + 4) % 7 + 7) % 7
    }

    var isWeekend: Bool {
        let weekday = weekdayIndex
        return weekday == 0 || weekday == 6
    }

    // MARK: ISO 8601 text

    /// Deliberately *not* locale-aware: this is the wire format Harvest parses, so it
    /// must stay ASCII digits with hyphens whatever the reader's region says.
    /// Anything shown to a person goes through a format style instead.
    public var description: String {
        guard (0...9999).contains(year), (0...99).contains(month), (0...99).contains(day) else {
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        let digits = [
            UInt8(ascii: "0") + UInt8(year / 1000), UInt8(ascii: "0") + UInt8(year / 100 % 10),
            UInt8(ascii: "0") + UInt8(year / 10 % 10), UInt8(ascii: "0") + UInt8(year % 10), UInt8(ascii: "-"),
            UInt8(ascii: "0") + UInt8(month / 10), UInt8(ascii: "0") + UInt8(month % 10), UInt8(ascii: "-"),
            UInt8(ascii: "0") + UInt8(day / 10), UInt8(ascii: "0") + UInt8(day % 10),
        ]
        return String(decoding: digits, as: UTF8.self)
    }

    public init?(iso: String) {
        if let parsed = Self.parseCanonical(iso) {
            self = parsed
            return
        }
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The `yyyy-MM-dd` form Harvest sends, read straight from the bytes. Anything else takes the slower, more lenient path.
    private static func parseCanonical(_ text: String) -> CalendarDate? {
        text.utf8.withContiguousStorageIfAvailable { bytes -> CalendarDate? in
            guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
            func digit(_ index: Int) -> Int? {
                let value = Int(bytes[index]) - Int(UInt8(ascii: "0"))
                return (0...9).contains(value) ? value : nil
            }
            guard let y0 = digit(0), let y1 = digit(1), let y2 = digit(2), let y3 = digit(3),
                  let m0 = digit(5), let m1 = digit(6), let d0 = digit(8), let d1 = digit(9)
            else { return nil }
            let month = m0 * 10 + m1
            let day = d0 * 10 + d1
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            return CalendarDate(year: ((y0 * 10 + y1) * 10 + y2) * 10 + y3, month: month, day: day)
        } ?? nil
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = CalendarDate(iso: text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)")
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// The account's `week_start_day`. Harvest only ever returns these three.
public enum Weekday: String, Sendable, Codable, CaseIterable {
    case saturday = "Saturday"
    case sunday = "Sunday"
    case monday = "Monday"

    /// `Calendar.firstWeekday` uses 1 = Sunday.
    var calendarIndex: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .saturday: 7
        }
    }
}
