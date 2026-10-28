import Foundation
import ScytheCore
import Testing
@testable import Scythe

@Suite("Entry timestamp label")
struct EntryTimestampTests {
    private let created = Date(timeIntervalSince1970: 1_793_112_060)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func label(spent: CalendarDate, locale: String = "en_US", calendar: Calendar? = nil) -> String {
        EntryTimestamp.label(
            createdAt: created, spentDate: spent, locale: Locale(identifier: locale), calendar: calendar ?? utc
        )
        .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test("an entry created on its own day shows only the time")
    func sameDay() {
        // Act & Assert
        #expect(label(spent: CalendarDate(year: 2026, month: 10, day: 27)) == "Created @ 2:41 PM")
    }

    @Test("an entry logged for another day names the day it was created")
    func otherDay() {
        // Act & Assert
        #expect(label(spent: CalendarDate(year: 2026, month: 10, day: 26)) == "Created @ 2:41 PM · Oct 27")
    }

    @Test("the time follows the locale's clock")
    func twentyFourHourLocale() {
        // Act & Assert
        #expect(label(spent: CalendarDate(year: 2026, month: 10, day: 27), locale: "en_GB") == "Created @ 14:41")
    }

    @Test("the day is judged in the calendar's own time zone")
    func timeZone() {
        // Arrange
        var tokyo = utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        // Act & Assert
        #expect(label(spent: CalendarDate(year: 2026, month: 10, day: 27), calendar: tokyo) == "Created @ 11:41 PM")
        #expect(label(spent: CalendarDate(year: 2026, month: 10, day: 28), calendar: tokyo) == "Created @ 11:41 PM · Oct 27")
    }
}
