import AppKit
import Foundation
import ScytheCore
import Testing
@testable import Scythe

@Suite("Entry date format")
@MainActor
struct EntryDateFormatTests {
    private let date = CalendarDate(year: 2026, month: 10, day: 27)
    private let usa = Locale(identifier: "en_US")

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func text(_ format: EntryDateFormat, locale: Locale? = nil) -> String {
        format.formatted(date, locale: locale ?? usa, calendar: utc)
    }

    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "EntryDateFormatTests-\(UUID().uuidString)")!
    }

    @Test("the default format names the weekday, month, day and year")
    func weekdayMonthDayYear() {
        // Act & Assert
        #expect(text(.weekdayMonthDayYear) == "Tue, Oct 27, 2026")
    }

    @Test("month, day and year leave the weekday out")
    func monthDayYear() {
        // Act & Assert
        #expect(text(.monthDayYear) == "Oct 27, 2026")
    }

    @Test("the numeric format is all digits")
    func numeric() {
        // Act & Assert
        #expect(text(.numeric) == "10/27/2026")
    }

    @Test("the numeric format follows the locale's order")
    func numericFollowsLocale() {
        // Act & Assert
        #expect(text(.numeric, locale: Locale(identifier: "en_GB")) == "27/10/2026")
    }

    @Test("the ISO format is year, month, day")
    func iso() {
        // Act & Assert
        #expect(text(.iso) == "2026-10-27")
    }

    @Test("the ISO format keeps ASCII digits in any locale")
    func isoIgnoresLocale() {
        // Act & Assert
        #expect(text(.iso, locale: Locale(identifier: "ar")) == "2026-10-27")
    }

    @Test("a fresh install shows the weekday format")
    func defaultsToWeekdayFormat() {
        // Act & Assert
        #expect(EntryDateFormatPreference(defaults: scratchDefaults()).format == .weekdayMonthDayYear)
    }

    @Test("the chosen format survives a relaunch")
    func persistsAcrossLaunches() {
        // Arrange
        let defaults = scratchDefaults()
        let preference = EntryDateFormatPreference(defaults: defaults)

        // Act
        preference.format = .iso

        // Assert
        #expect(EntryDateFormatPreference(defaults: defaults).format == .iso)
    }

    @Test("an unrecognised stored format falls back to the default")
    func ignoresUnknownStoredValue() {
        // Arrange
        let defaults = scratchDefaults()
        defaults.set("tuesday", forKey: "entryDateFormat")

        // Act & Assert
        #expect(EntryDateFormatPreference(defaults: defaults).format == .weekdayMonthDayYear)
    }

    @Test("the menu offers every format and checks the current one")
    func menuChecksCurrent() {
        // Arrange
        let preference = EntryDateFormatPreference(defaults: scratchDefaults())
        preference.format = .monthDayYear
        let menu = NSMenu()

        // Act
        DateColumnMenu.fill(menu, for: preference, target: nil)

        // Assert
        let choices = menu.items.filter { $0.representedObject != nil }
        #expect(choices.count == EntryDateFormat.allCases.count)
        #expect(choices.filter { $0.state == .on }.map { $0.representedObject as? String } == ["monthDayYear"])
    }

    @Test("choosing a menu item changes the preference")
    func choosingChangesPreference() {
        // Arrange
        let preference = EntryDateFormatPreference(defaults: scratchDefaults())
        let item = NSMenuItem()
        item.representedObject = EntryDateFormat.numeric.rawValue

        // Act
        DateColumnMenu.choose(item, in: preference)

        // Assert
        #expect(preference.format == .numeric)
    }
}
