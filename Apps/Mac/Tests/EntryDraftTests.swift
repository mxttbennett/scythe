import Foundation
import ScytheCore
import Testing
@testable import Scythe

@Suite("Entry draft")
struct EntryDraftTests {
    private let today = CalendarDate(year: 2026, month: 10, day: 27)
    private let us = Locale(identifier: "en_US")

    @Test("a blank duration today starts a timer")
    func blankTodayStartsTimer() {
        // Act
        let action = EntryDraft.action(hoursText: "", date: today, today: today, locale: us)

        // Assert
        #expect(action == .startTimer)
    }

    @Test("spaces alone count as blank")
    func spacesAreBlank() {
        // Act
        let action = EntryDraft.action(hoursText: "   ", date: today, today: today, locale: us)

        // Assert
        #expect(action == .startTimer)
    }

    @Test("a blank duration on another day cannot be sent, since a timer runs now")
    func blankOtherDayIsNotReady() {
        // Act
        let action = EntryDraft.action(hoursText: "", date: today.adding(days: -1), today: today, locale: us)

        // Assert
        #expect(action == nil)
    }

    @Test("hours and minutes are logged as decimal hours")
    func hoursAndMinutes() {
        // Act
        let action = EntryDraft.action(hoursText: "1:30", date: today.adding(days: -3), today: today, locale: us)

        // Assert
        #expect(action == .log(hours: 1.5))
    }

    @Test("a decimal is logged as it is")
    func decimal() {
        // Act
        let action = EntryDraft.action(hoursText: "2.25", date: today, today: today, locale: us)

        // Assert
        #expect(action == .log(hours: 2.25))
    }

    @Test("zero hours is not an entry")
    func zeroIsNotReady() {
        // Act
        let action = EntryDraft.action(hoursText: "0", date: today, today: today, locale: us)

        // Assert
        #expect(action == nil)
    }

    @Test("only a logged entry carries hours")
    func hoursOfAnAction() {
        // Act & Assert
        #expect(EntryAction.log(hours: 1.5).hours == 1.5)
        #expect(EntryAction.startTimer.hours == nil)
    }

    @Test("text that is not a duration is not ready")
    func nonsenseIsNotReady() {
        // Act
        let action = EntryDraft.action(hoursText: "soon", date: today, today: today, locale: us)

        // Assert
        #expect(action == nil)
    }
}
