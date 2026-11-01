import Foundation
import Testing
@testable import ScytheCore

@Suite("ISO 8601 timestamps")
struct ISO8601TimestampTests {
    @Test("reads Harvest's form to the same instant Foundation does", arguments: [
        "2026-10-31T14:22:33Z", "1970-01-01T00:00:00Z", "2000-02-29T23:59:59Z", "2024-02-29T12:00:00Z",
        "2038-01-19T03:14:08Z", "1999-12-31T23:59:59Z", "2100-03-01T00:00:00Z", "2026-01-01T00:00:00Z",
    ])
    func matchesFoundation(text: String) throws {
        // Act
        let fast = try #require(ISO8601Timestamp.date(from: text))

        // Assert
        #expect(fast == (try Date(text, strategy: .iso8601)))
    }

    @Test("agrees with Foundation across every day of several years")
    func sweep() throws {
        // Arrange
        var day = CalendarDate(year: 2019, month: 12, day: 25)

        for step in 0..<2400 {
            let text = String(format: "%@T%02d:%02d:%02dZ", day.description, step % 24, (step * 7) % 60, (step * 13) % 60)

            // Act
            let fast = try #require(ISO8601Timestamp.date(from: text))

            // Assert
            #expect(fast == (try Date(text, strategy: .iso8601)), "\(text)")
            day = day.adding(days: 1)
        }
    }

    @Test("leaves anything else to the general parser", arguments: [
        "2026-10-31T14:22:33.123Z", "2026-10-31T14:22:33+01:00", "2026-10-31 14:22:33Z", "2026-02-30T10:00:00Z",
        "2026-13-01T10:00:00Z", "2026-10-31T24:00:00Z", "2026-10-31T10:60:00Z", "2026-10-31T10:00:60Z", "not a date",
        "", "2026-10-31T14:22:3zZ", "２０２６-10-31T14:22:33Z",
    ])
    func declines(text: String) {
        // Act & Assert
        #expect(ISO8601Timestamp.date(from: text) == nil)
    }
}
