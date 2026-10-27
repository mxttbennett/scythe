import Foundation

public struct TimesheetRow: Identifiable, Hashable, Sendable {
    public var project: Reference
    public var task: Reference
    public var client: Reference?
    /// Seven lists, one per day of the week, of the entries behind each cell.
    public var entriesByDay: [[TrackedEntry]]
    public var hoursByDay: [Double]

    public var id: String { "\(project.id):\(task.id)" }
    public var total: Double { hoursByDay.reduce(0, +) }
}

/// One week as a grid: a row for each project and task, a column for each day.
public struct Timesheet: Sendable {
    public let weekStart: CalendarDate
    public let days: [CalendarDate]
    public let rows: [TimesheetRow]

    public var dayTotals: [Double] {
        days.indices.map { day in rows.reduce(0) { $0 + $1.hoursByDay[day] } }
    }

    public var total: Double { rows.reduce(0) { $0 + $1.total } }

    public static func build(from entries: [TrackedEntry], weekStart: CalendarDate, asOf now: Date = Date()) -> Timesheet {
        let days = (0..<7).map { weekStart.adding(days: $0) }
        let end = days[6]
        var rows: [String: TimesheetRow] = [:]

        for entry in entries where (weekStart...end).contains(entry.spentDate) {
            let column = entry.spentDate.daysSince(weekStart)
            let id = "\(entry.project.id):\(entry.task.id)"
            var row = rows[id] ?? TimesheetRow(
                project: entry.project, task: entry.task, client: entry.client,
                entriesByDay: Array(repeating: [], count: 7), hoursByDay: Array(repeating: 0, count: 7)
            )
            row.entriesByDay[column].append(entry)
            row.hoursByDay[column] += entry.hours(asOf: now)
            rows[id] = row
        }

        let sorted = rows.values.sorted {
            ($0.client?.name ?? "", $0.project.name, $0.task.name) < ($1.client?.name ?? "", $1.project.name, $1.task.name)
        }
        return Timesheet(weekStart: weekStart, days: days, rows: sorted)
    }
}
