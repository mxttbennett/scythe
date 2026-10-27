import Foundation

public enum DatePreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case today, thisWeek, lastWeek, last7Days, last30Days, last90Days, thisMonth, lastMonth, thisYear, lastYear

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .last90Days: "Last 90 days"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        }
    }

    public func range(
        today: CalendarDate,
        weekStart: Weekday,
        calendar: Calendar = .current
    ) -> ClosedRange<CalendarDate> {
        switch self {
        case .today:
            return today...today
        case .thisWeek:
            let start = today.startOfWeek(weekStart: weekStart, in: calendar)
            return start...start.adding(days: 6, in: calendar)
        case .lastWeek:
            let start = today.startOfWeek(weekStart: weekStart, in: calendar).adding(days: -7, in: calendar)
            return start...start.adding(days: 6, in: calendar)
        case .last7Days:
            return today.adding(days: -6, in: calendar)...today
        case .last30Days:
            return today.adding(days: -29, in: calendar)...today
        case .last90Days:
            return today.adding(days: -89, in: calendar)...today
        case .thisMonth:
            return Self.month(of: today, offset: 0, calendar: calendar)
        case .lastMonth:
            return Self.month(of: today, offset: -1, calendar: calendar)
        case .thisYear:
            return CalendarDate(year: today.year, month: 1, day: 1)...CalendarDate(year: today.year, month: 12, day: 31)
        case .lastYear:
            return CalendarDate(year: today.year - 1, month: 1, day: 1)...CalendarDate(year: today.year - 1, month: 12, day: 31)
        }
    }

    private static func month(of date: CalendarDate, offset: Int, calendar: Calendar) -> ClosedRange<CalendarDate> {
        let index = date.year * 12 + (date.month - 1) + offset
        let first = CalendarDate(year: index / 12, month: index % 12 + 1, day: 1)
        let nextIndex = index + 1
        let next = CalendarDate(year: nextIndex / 12, month: nextIndex % 12 + 1, day: 1)
        return first...next.adding(days: -1, in: calendar)
    }
}

/// Which days a filter looks at. A preset stays relative, so a saved "This month" is
/// still this month when it is reopened.
public enum Period: Codable, Hashable, Sendable {
    case all
    case preset(DatePreset)
    case custom(ClosedRange<CalendarDate>)

    public func range(today: CalendarDate, weekStart: Weekday, calendar: Calendar = .current) -> ClosedRange<CalendarDate>? {
        switch self {
        case .all: nil
        case .preset(let preset): preset.range(today: today, weekStart: weekStart, calendar: calendar)
        case .custom(let range): range
        }
    }
}

public struct EntryFilter: Codable, Hashable, Sendable {
    public var period: Period
    public var text: String
    public var projectIDs: Set<Int>
    public var clientIDs: Set<Int>
    public var taskIDs: Set<Int>
    /// Nil keeps both billable and non-billable entries.
    public var billable: Bool?

    public init(
        period: Period = .all,
        text: String = "",
        projectIDs: Set<Int> = [],
        clientIDs: Set<Int> = [],
        taskIDs: Set<Int> = [],
        billable: Bool? = nil
    ) {
        self.period = period
        self.text = text
        self.projectIDs = projectIDs
        self.clientIDs = clientIDs
        self.taskIDs = taskIDs
        self.billable = billable
    }

    public var isEmpty: Bool { self == EntryFilter() }

    public func apply(
        to entries: [TrackedEntry],
        today: CalendarDate = .today(),
        weekStart: Weekday = .monday
    ) -> [TrackedEntry] {
        let range = period.range(today: today, weekStart: weekStart)
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in
            if let range, !range.contains(entry.spentDate) { return false }
            if !projectIDs.isEmpty, !projectIDs.contains(entry.project.id) { return false }
            if !taskIDs.isEmpty, !taskIDs.contains(entry.task.id) { return false }
            if !clientIDs.isEmpty, !(entry.client.map { clientIDs.contains($0.id) } ?? false) { return false }
            if let billable, entry.isBillable != billable { return false }
            guard !words.isEmpty else { return true }
            let haystack = [entry.notes, entry.project.name, entry.client?.name, entry.task.name]
                .compactMap { $0 }
                .joined(separator: " ")
            return words.allSatisfy {
                haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
