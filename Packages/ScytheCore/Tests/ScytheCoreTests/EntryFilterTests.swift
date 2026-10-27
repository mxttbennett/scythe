import Foundation
import Testing
@testable import ScytheCore

@Suite("Entry filter")
struct EntryFilterTests {
    private let today = CalendarDate(year: 2026, month: 10, day: 27)

    private func entry(
        _ id: Int64 = 1,
        on date: CalendarDate,
        client: (Int, String)? = (1, "EnterBridge"),
        project: (Int, String) = (10, "Cogniform Development"),
        task: (Int, String) = (20, "Software Development"),
        notes: String? = nil,
        billable: Bool = true
    ) -> TrackedEntry {
        TrackedEntry(
            id: .server(id),
            project: Reference(id: project.0, name: project.1),
            task: Reference(id: task.0, name: task.1),
            client: client.map { Reference(id: $0.0, name: $0.1) },
            notes: notes, spentDate: date, bankedHours: 1, isRunning: false, isBillable: billable
        )
    }

    private func apply(_ filter: EntryFilter, to entries: [TrackedEntry]) -> [Int64] {
        filter.apply(to: entries, today: today, weekStart: .monday).compactMap(\.id.serverID)
    }

    @Test("an empty filter keeps everything")
    func emptyKeepsAll() {
        // Act
        let kept = apply(EntryFilter(), to: [entry(1, on: today), entry(2, on: today.adding(days: -400))])

        // Assert
        #expect(kept == [1, 2])
    }

    @Test("text matches the notes, project, client and task, ignoring case")
    func textSearchesEverything() {
        // Arrange
        let entries = [
            entry(1, on: today, notes: "COG-1553: Avoid updating a disposed page"),
            entry(2, on: today, project: (11, "Airgas Canadian Conversion")),
            entry(3, on: today, client: (2, "Neo Insulation")),
            entry(4, on: today, task: (21, "Meetings")),
        ]

        // Act & Assert
        #expect(apply(EntryFilter(text: "disposed"), to: entries) == [1])
        #expect(apply(EntryFilter(text: "AIRGAS"), to: entries) == [2])
        #expect(apply(EntryFilter(text: "insulation"), to: entries) == [3])
        #expect(apply(EntryFilter(text: "meetings"), to: entries) == [4])
    }

    @Test("every word of the text has to match somewhere")
    func textWordsAreAnded() {
        // Arrange
        let entries = [
            entry(1, on: today, notes: "review the PR"),
            entry(2, on: today, notes: "review the design"),
        ]

        // Act
        let kept = apply(EntryFilter(text: "review pr"), to: entries)

        // Assert
        #expect(kept == [1])
    }

    @Test("projects, clients and tasks narrow by id")
    func idFilters() {
        // Arrange
        let entries = [
            entry(1, on: today),
            entry(2, on: today, client: (2, "Other"), project: (11, "Other project"), task: (21, "Other task")),
        ]

        // Act & Assert
        #expect(apply(EntryFilter(projectIDs: [11]), to: entries) == [2])
        #expect(apply(EntryFilter(clientIDs: [1]), to: entries) == [1])
        #expect(apply(EntryFilter(taskIDs: [20, 21]), to: entries) == [1, 2])
    }

    @Test("an entry without a client is excluded by a client filter")
    func missingClientNeverMatches() {
        // Act
        let kept = apply(EntryFilter(clientIDs: [1]), to: [entry(1, on: today, client: nil)])

        // Assert
        #expect(kept.isEmpty)
    }

    @Test("billable narrows to one side")
    func billableFilter() {
        // Arrange
        let entries = [entry(1, on: today, billable: true), entry(2, on: today, billable: false)]

        // Act & Assert
        #expect(apply(EntryFilter(billable: true), to: entries) == [1])
        #expect(apply(EntryFilter(billable: false), to: entries) == [2])
    }

    @Test("a custom period includes both ends")
    func customPeriodIsInclusive() {
        // Arrange
        let from = today.adding(days: -2)
        let entries = [
            entry(1, on: from.adding(days: -1)), entry(2, on: from),
            entry(3, on: today), entry(4, on: today.adding(days: 1)),
        ]

        // Act
        let kept = apply(EntryFilter(period: .custom(from...today)), to: entries)

        // Assert
        #expect(kept == [2, 3])
    }

    @Test("this week starts on the configured weekday")
    func thisWeekUsesWeekStart() {
        // Arrange: 2026-10-27 is a Tuesday.
        let monday = CalendarDate(year: 2026, month: 10, day: 26)
        let sunday = CalendarDate(year: 2026, month: 10, day: 25)

        // Act
        let mondayStart = DatePreset.thisWeek.range(today: today, weekStart: .monday)
        let sundayStart = DatePreset.thisWeek.range(today: today, weekStart: .sunday)

        // Assert
        #expect(mondayStart.lowerBound == monday)
        #expect(sundayStart.lowerBound == sunday)
    }

    @Test("last month is the whole previous calendar month")
    func lastMonthRange() {
        // Act
        let range = DatePreset.lastMonth.range(today: today, weekStart: .monday)

        // Assert
        #expect(range == CalendarDate(year: 2026, month: 9, day: 1)...CalendarDate(year: 2026, month: 9, day: 30))
    }

    @Test("last month from January is December of the year before")
    func lastMonthAcrossYears() {
        // Act
        let range = DatePreset.lastMonth.range(today: CalendarDate(year: 2026, month: 1, day: 15), weekStart: .monday)

        // Assert
        #expect(range == CalendarDate(year: 2025, month: 12, day: 1)...CalendarDate(year: 2025, month: 12, day: 31))
    }

    @Test("last 30 days ends today and spans thirty days")
    func lastThirtyDays() {
        // Act
        let range = DatePreset.last30Days.range(today: today, weekStart: .monday)

        // Assert
        #expect(range.upperBound == today)
        #expect(range.lowerBound == today.adding(days: -29))
    }

    @Test("a filter survives encoding, which is how saved queries keep it")
    func codableRoundTrip() throws {
        // Arrange
        let filter = EntryFilter(
            period: .preset(.lastMonth), text: "cogniform", projectIDs: [10], clientIDs: [1], taskIDs: [20], billable: false
        )

        // Act
        let decoded = try JSONDecoder().decode(EntryFilter.self, from: JSONEncoder().encode(filter))

        // Assert
        #expect(decoded == filter)
    }
}
