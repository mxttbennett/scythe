import Foundation
import Testing
@testable import SheavesCore

@Suite("Entry analytics")
struct EntryAnalyticsTests {
    private let monday = CalendarDate(year: 2026, month: 10, day: 26)

    private func entry(
        _ id: Int64,
        on date: CalendarDate,
        hours: Double,
        client: (Int, String)? = (1, "EnterBridge"),
        project: (Int, String) = (10, "Cogniform"),
        task: (Int, String) = (20, "Development"),
        billable: Bool = true
    ) -> TrackedEntry {
        TrackedEntry(
            id: .server(id),
            project: Reference(id: project.0, name: project.1),
            task: Reference(id: task.0, name: task.1),
            client: client.map { Reference(id: $0.0, name: $0.1) },
            spentDate: date, bankedHours: hours, isRunning: false, isBillable: billable
        )
    }

    @Test("totals split billable from non-billable hours")
    func totals() {
        // Arrange
        let analytics = EntryAnalytics([
            entry(1, on: monday, hours: 3, billable: true),
            entry(2, on: monday, hours: 1, billable: false),
        ])

        // Assert
        #expect(analytics.totalHours == 4)
        #expect(analytics.billableHours == 3)
        #expect(analytics.nonBillableHours == 1)
        #expect(analytics.billableShare == 0.75)
    }

    @Test("an empty set has no share and no average")
    func emptySet() {
        // Arrange
        let analytics = EntryAnalytics([])

        // Assert
        #expect(analytics.billableShare == 0)
        #expect(analytics.averagePerActiveDay == 0)
    }

    @Test("the average counts only days that have entries")
    func averagePerActiveDay() {
        // Arrange
        let analytics = EntryAnalytics([
            entry(1, on: monday, hours: 2),
            entry(2, on: monday, hours: 2),
            entry(3, on: monday.adding(days: 3), hours: 4),
        ])

        // Assert
        #expect(analytics.activeDays == 2)
        #expect(analytics.averagePerActiveDay == 4)
    }

    @Test("projects are ranked by hours and carry their client")
    func byProject() {
        // Arrange
        let analytics = EntryAnalytics([
            entry(1, on: monday, hours: 1, project: (10, "Small")),
            entry(2, on: monday, hours: 5, project: (11, "Large")),
            entry(3, on: monday, hours: 2, project: (11, "Large")),
        ])

        // Act
        let buckets = analytics.byProject()

        // Assert
        #expect(buckets.map(\.name) == ["Large", "Small"])
        #expect(buckets.first?.hours == 7)
        #expect(buckets.first?.entryCount == 2)
        #expect(buckets.first?.detail == "EnterBridge")
    }

    @Test("entries without a client group under one name")
    func byClientWithoutClient() {
        // Arrange
        let analytics = EntryAnalytics([entry(1, on: monday, hours: 1, client: nil)])

        // Act
        let buckets = analytics.byClient()

        // Assert
        #expect(buckets.map(\.name) == ["No client"])
    }

    @Test("days between the first and last entry appear with zero hours")
    func byDayFillsGaps() {
        // Arrange
        let analytics = EntryAnalytics([
            entry(1, on: monday, hours: 2),
            entry(2, on: monday.adding(days: 2), hours: 3),
        ])

        // Act
        let days = analytics.byDay()

        // Assert
        #expect(days.map(\.hours) == [2, 0, 3])
        #expect(days.map(\.start) == [monday, monday.adding(days: 1), monday.adding(days: 2)])
    }

    @Test("weeks start on the configured weekday and gaps are filled")
    func byWeek() {
        // Arrange
        let analytics = EntryAnalytics([
            entry(1, on: monday, hours: 2),
            entry(2, on: monday.adding(days: 15), hours: 4),
        ])

        // Act
        let weeks = analytics.byWeek(weekStart: .monday)

        // Assert
        #expect(weeks.map(\.start) == [monday, monday.adding(days: 7), monday.adding(days: 14)])
        #expect(weeks.map(\.hours) == [2, 0, 4])
    }

    @Test("months run across a year boundary")
    func byMonth() {
        // Arrange
        let analytics = EntryAnalytics([
            entry(1, on: CalendarDate(year: 2025, month: 12, day: 20), hours: 2),
            entry(2, on: CalendarDate(year: 2026, month: 2, day: 3), hours: 6, billable: false),
        ])

        // Act
        let months = analytics.byMonth()

        // Assert
        #expect(months.map(\.start) == [
            CalendarDate(year: 2025, month: 12, day: 1),
            CalendarDate(year: 2026, month: 1, day: 1),
            CalendarDate(year: 2026, month: 2, day: 1),
        ])
        #expect(months.map(\.hours) == [2, 0, 6])
        #expect(months.map(\.billableHours) == [2, 0, 0])
    }
}

@Suite("Timesheet")
struct TimesheetTests {
    private let monday = CalendarDate(year: 2026, month: 10, day: 26)

    private func entry(
        _ id: Int64,
        on date: CalendarDate,
        hours: Double,
        project: (Int, String) = (10, "Cogniform"),
        task: (Int, String) = (20, "Development")
    ) -> TrackedEntry {
        TrackedEntry(
            id: .server(id),
            project: Reference(id: project.0, name: project.1),
            task: Reference(id: task.0, name: task.1),
            client: Reference(id: 1, name: "EnterBridge"),
            spentDate: date, bankedHours: hours, isRunning: false
        )
    }

    @Test("a week has seven days from its start")
    func sevenDays() {
        // Act
        let sheet = Timesheet.build(from: [], weekStart: monday)

        // Assert
        #expect(sheet.days.count == 7)
        #expect(sheet.days.first == monday)
        #expect(sheet.days.last == monday.adding(days: 6))
    }

    @Test("a project and task get one row with hours in the right column")
    func rowsAndColumns() {
        // Arrange
        let entries = [
            entry(1, on: monday, hours: 2),
            entry(2, on: monday, hours: 1),
            entry(3, on: monday.adding(days: 2), hours: 4),
            entry(4, on: monday.adding(days: 1), hours: 3, task: (21, "Meetings")),
        ]

        // Act
        let sheet = Timesheet.build(from: entries, weekStart: monday)

        // Assert
        #expect(sheet.rows.count == 2)
        let development = sheet.rows.first { $0.task.id == 20 }
        #expect(development?.hoursByDay == [3, 0, 4, 0, 0, 0, 0])
        #expect(development?.total == 7)
        #expect(sheet.dayTotals == [3, 3, 4, 0, 0, 0, 0])
        #expect(sheet.total == 10)
    }

    @Test("entries outside the week are left out")
    func ignoresOtherWeeks() {
        // Arrange
        let entries = [entry(1, on: monday.adding(days: -1), hours: 5), entry(2, on: monday.adding(days: 7), hours: 5)]

        // Act
        let sheet = Timesheet.build(from: entries, weekStart: monday)

        // Assert
        #expect(sheet.rows.isEmpty)
        #expect(sheet.total == 0)
    }

    @Test("a cell remembers which entries it was made from")
    func cellKeepsEntries() {
        // Arrange
        let entries = [entry(1, on: monday, hours: 2), entry(2, on: monday, hours: 1)]

        // Act
        let sheet = Timesheet.build(from: entries, weekStart: monday)

        // Assert
        #expect(sheet.rows.first?.entriesByDay[0].count == 2)
        #expect(sheet.rows.first?.entriesByDay[1].isEmpty == true)
    }
}

@Suite("CSV export")
struct CSVExportTests {
    private func entry(notes: String?, hours: Double = 1.5, billable: Bool = true) -> TrackedEntry {
        TrackedEntry(
            id: .server(1),
            project: Reference(id: 10, name: "Cogniform"),
            task: Reference(id: 20, name: "Development"),
            client: Reference(id: 1, name: "EnterBridge"),
            notes: notes, spentDate: CalendarDate(year: 2026, month: 10, day: 27),
            bankedHours: hours, isRunning: false, isBillable: billable
        )
    }

    @Test("the first line names the columns")
    func header() {
        // Act
        let csv = CSVExport.entries([])

        // Assert
        #expect(csv == "Date,Client,Project,Task,Notes,Hours,Billable\n")
    }

    @Test("a row has the date, names, notes, decimal hours and billable flag")
    func plainRow() {
        // Act
        let csv = CSVExport.entries([entry(notes: "Review")])

        // Assert
        #expect(csv.hasSuffix("2026-10-27,EnterBridge,Cogniform,Development,Review,1.50,yes\n"))
    }

    @Test("commas, quotes and line breaks are quoted")
    func quoting() {
        // Act
        let csv = CSVExport.entries([entry(notes: "He said \"ship it\", then\nleft")])

        // Assert
        #expect(csv.contains("\"He said \"\"ship it\"\", then\nleft\""))
    }

    @Test("an entry with no notes leaves the field empty")
    func missingNotes() {
        // Act
        let csv = CSVExport.entries([entry(notes: nil, billable: false)])

        // Assert
        #expect(csv.hasSuffix("Development,,1.50,no\n"))
    }
}
