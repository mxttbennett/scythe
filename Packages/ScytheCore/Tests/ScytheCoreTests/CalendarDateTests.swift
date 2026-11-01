import Foundation
import Testing
@testable import ScytheCore

@Suite("CalendarDate")
struct CalendarDateTests {
    @Test("round-trips ISO 8601 text")
    func roundTrip() throws {
        let date = try #require(CalendarDate(iso: "2026-08-29"))
        #expect(date.year == 2026)
        #expect(date.month == 8)
        #expect(date.day == 29)
        #expect(date.description == "2026-08-29")
    }

    @Test("pads single digits")
    func padding() {
        #expect(CalendarDate(year: 2026, month: 1, day: 5).description == "2026-01-05")
    }

    @Test("rejects nonsense")
    func rejectsNonsense() {
        #expect(CalendarDate(iso: "not-a-date") == nil)
        #expect(CalendarDate(iso: "2026-13-01") == nil)
        #expect(CalendarDate(iso: "2026-08") == nil)
    }

    @Test("orders chronologically")
    func ordering() {
        let earlier = CalendarDate(year: 2026, month: 8, day: 29)
        let later = CalendarDate(year: 2026, month: 9, day: 1)
        #expect(earlier < later)
        #expect(!(later < earlier))
    }

    @Test("adds days across a month boundary")
    func addingDays() {
        let end = CalendarDate(year: 2026, month: 8, day: 31)
        #expect(end.adding(days: 1) == CalendarDate(year: 2026, month: 9, day: 1))
        #expect(end.adding(days: -31) == CalendarDate(year: 2026, month: 7, day: 31))
    }

    @Test("adds days across a leap day")
    func leapDay() {
        let date = CalendarDate(year: 2028, month: 2, day: 28)
        #expect(date.adding(days: 1) == CalendarDate(year: 2028, month: 2, day: 29))
    }

    /// The whole point of the type: a day must not drift when the machine is east or
    /// west of UTC, which is exactly what storing `spent_date` as a `Date` would cause.
    @Test("holds its day in any time zone", arguments: ["Pacific/Kiritimati", "UTC", "Pacific/Midway"])
    func stableAcrossTimeZones(zoneName: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zoneName))
        let day = CalendarDate(year: 2026, month: 8, day: 29)
        #expect(CalendarDate(day.startOfDay(in: calendar), in: calendar) == day)
    }

    @Test("finds the start of the week for each Harvest week-start setting")
    func startOfWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // 2026-08-29 is a Saturday.
        let saturday = CalendarDate(year: 2026, month: 8, day: 29)
        #expect(saturday.startOfWeek(weekStart: .monday, in: calendar) == CalendarDate(year: 2026, month: 8, day: 24))
        #expect(saturday.startOfWeek(weekStart: .sunday, in: calendar) == CalendarDate(year: 2026, month: 8, day: 23))
        #expect(saturday.startOfWeek(weekStart: .saturday, in: calendar) == saturday)
    }
}

@Suite("CalendarDate fast paths")
struct CalendarDateFastPathTests {
    private static let reference: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let days: [CalendarDate] = {
        let start = CalendarDate(year: 1995, month: 1, day: 1)
        return stride(from: 0, to: 365 * 46, by: 3).map { start.adding(days: $0, in: reference) }
    }()

    @Test("adds days exactly as the calendar does")
    func addingMatchesCalendar() {
        // Arrange
        let calendar = Self.reference

        for day in Self.days {
            for offset in [-400, -7, -1, 0, 1, 6, 7, 45, 400] {
                // Act
                let shifted = day.adding(days: offset, in: calendar)

                // Assert
                let expected = calendar.date(byAdding: .day, value: offset, to: day.startOfDay(in: calendar))!
                #expect(shifted == CalendarDate(expected, in: calendar), "\(day) + \(offset)")
            }
        }
    }

    @Test("counts the days between two dates exactly as the calendar does")
    func daysSinceMatchesCalendar() {
        // Arrange
        let calendar = Self.reference
        let anchor = CalendarDate(year: 2026, month: 10, day: 31)

        for day in Self.days {
            // Act
            let gap = day.daysSince(anchor, in: calendar)

            // Assert
            let expected = calendar.dateComponents([.day], from: anchor.startOfDay(in: calendar), to: day.startOfDay(in: calendar)).day
            #expect(gap == expected, "\(day)")
        }
    }

    @Test("finds the start of the week exactly as the calendar does", arguments: Weekday.allCases)
    func startOfWeekMatchesCalendar(weekStart: Weekday) {
        // Arrange
        var calendar = Self.reference
        calendar.firstWeekday = weekStart.calendarIndex

        for day in Self.days {
            // Act
            let start = day.startOfWeek(weekStart: weekStart, in: Self.reference)

            // Assert
            let interval = calendar.dateInterval(of: .weekOfYear, for: day.startOfDay(in: calendar))!
            #expect(start == CalendarDate(interval.start, in: calendar), "\(day) from \(weekStart)")
        }
    }

    @Test("knows which days are weekends")
    func weekendMatchesCalendar() {
        // Arrange
        let calendar = Self.reference

        for day in Self.days {
            // Act
            let weekday = calendar.component(.weekday, from: day.startOfDay(in: calendar))

            // Assert
            #expect(day.isWeekend == (weekday == 1 || weekday == 7), "\(day)")
        }
    }

    @Test("still handles calendars that are not Gregorian")
    func nonGregorianFallback() {
        // Arrange
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = TimeZone(identifier: "UTC")!
        let day = CalendarDate(year: 5787, month: 2, day: 10)

        // Act
        let shifted = day.adding(days: 30, in: hebrew)

        // Assert
        let expected = hebrew.date(byAdding: .day, value: 30, to: day.startOfDay(in: hebrew))!
        #expect(shifted == CalendarDate(expected, in: hebrew))
        #expect(shifted.daysSince(day, in: hebrew) == 30)
    }

    @Test("writes the ISO text Harvest parses", arguments: [
        (1, 1, 1, "0001-01-01"), (2026, 1, 5, "2026-01-05"), (2026, 12, 31, "2026-12-31"), (9999, 12, 31, "9999-12-31"),
    ])
    func descriptionIsPaddedASCII(year: Int, month: Int, day: Int, text: String) {
        // Act & Assert
        #expect(CalendarDate(year: year, month: month, day: day).description == text)
        #expect(CalendarDate(iso: text) == CalendarDate(year: year, month: month, day: day))
    }

    @Test("writes years outside four digits the way printf does")
    func descriptionOutsideFourDigits() {
        // Act & Assert
        #expect(CalendarDate(year: 12345, month: 1, day: 5).description == "12345-01-05")
        #expect(CalendarDate(year: -5, month: 1, day: 5).description == "-005-01-05")
    }

    @Test("keeps the permissive ISO reading for odd but valid text")
    func lenientISO() {
        // Act & Assert
        #expect(CalendarDate(iso: "2026-8-5") == CalendarDate(year: 2026, month: 8, day: 5))
        #expect(CalendarDate(iso: "2026-08-5x") == nil)
        #expect(CalendarDate(iso: "２０２６-08-05") == nil)
        #expect(CalendarDate(iso: "2026-00-05") == nil)
        #expect(CalendarDate(iso: "2026-08-32") == nil)
        #expect(CalendarDate(iso: "2026-08-050") == nil)
    }
}

@Suite("Hours formatting")
struct HoursFormattingTests {
    /// Pinned so the suite does not depend on the machine's region settings.
    private let english = Locale(identifier: "en_US")

    @Test("formats as hours and minutes")
    func hoursMinutes() {
        #expect(1.4.formattedHours(.hoursMinutes, locale: english) == "1:24")
        #expect(0.0.formattedHours(.hoursMinutes, locale: english) == "0:00")
        #expect(10.5.formattedHours(.hoursMinutes, locale: english) == "10:30")
    }

    /// Rounding to minutes before splitting keeps 0:60 from ever appearing.
    @Test("never renders sixty minutes")
    func neverSixtyMinutes() {
        #expect(0.99999.formattedHours(.hoursMinutes, locale: english) == "1:00")
        #expect(1.99999.formattedHours(.hoursMinutes, locale: english) == "2:00")
    }

    @Test("formats as decimal hours")
    func decimal() {
        #expect(1.4.formattedHours(.decimal, locale: english) == "1.40")
        #expect(0.25.formattedHours(.decimal, locale: english) == "0.25")
    }

    @Test("clamps negative durations")
    func negatives() {
        #expect((-1.0).formattedHours(.hoursMinutes, locale: english) == "0:00")
    }

    /// Decimal separators and digits are not universal: a hand-rolled "%.2f" gives
    /// a French user "1.40" where they expect "1,40".
    @Test("respects the reader's locale")
    func respectsLocale() {
        #expect(1.4.formattedHours(.decimal, locale: Locale(identifier: "fr_FR")) == "1,40")
        #expect(1.4.formattedHours(.decimal, locale: Locale(identifier: "de_DE")) == "1,40")
        // Arabic-Indic digits, which the colon form needs too.
        #expect(1.4.formattedHours(.hoursMinutes, locale: Locale(identifier: "ar_EG")) == "١:٢٤")
    }
}

@Suite("Hours parsing")
struct HoursParsingTests {
    private let english = Locale(identifier: "en_US")

    @Test("reads what people type")
    func readsCommonForms() {
        #expect(Double.hours(parsing: "1", locale: english) == 1.0)
        #expect(Double.hours(parsing: "1:30", locale: english) == 1.5)
        #expect(Double.hours(parsing: ":45", locale: english) == 0.75)
        #expect(Double.hours(parsing: "1:5", locale: english) == 1.0 + 5.0 / 60)
        #expect(Double.hours(parsing: "0:00", locale: english) == 0)
        #expect(Double.hours(parsing: " 2 ", locale: english) == 2.0)
        #expect(Double.hours(parsing: "1.5", locale: english) == 1.5)
    }

    @Test("respects the typist's locale")
    func respectsLocale() {
        #expect(Double.hours(parsing: "1,5", locale: Locale(identifier: "fr_FR")) == 1.5)
        #expect(Double.hours(parsing: "1,5", locale: Locale(identifier: "de_DE")) == 1.5)
    }

    @Test("rejects what it cannot honestly read")
    func rejectsJunk() {
        #expect(Double.hours(parsing: "", locale: english) == nil)
        #expect(Double.hours(parsing: "   ", locale: english) == nil)
        #expect(Double.hours(parsing: "abc", locale: english) == nil)
        #expect(Double.hours(parsing: "-1", locale: english) == nil)
        #expect(Double.hours(parsing: "1:75", locale: english) == nil)
        #expect(Double.hours(parsing: "1:-5", locale: english) == nil)
    }

    /// The edit field prefills with the formatted duration, so whatever the app
    /// displays must read back as the value it displayed.
    @Test("round-trips what the app displays")
    func roundTripsDisplay() {
        for identifier in ["en_US", "fr_FR", "ar_EG"] {
            let locale = Locale(identifier: identifier)
            for hours in [0.0, 0.25, 1.4, 10.5] {
                let shown = hours.formattedHours(.hoursMinutes, locale: locale)
                #expect(Double.hours(parsing: shown, locale: locale) == hours, "\(identifier) \(shown)")
            }
            let decimal = 1.4.formattedHours(.decimal, locale: locale)
            #expect(Double.hours(parsing: decimal, locale: locale) == 1.4, "\(identifier) \(decimal)")
        }
    }
}
