import Foundation

public struct HoursBucket: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// A project's client, so two projects with one name stay distinguishable.
    public var detail: String?
    public var hours: Double
    public var billableHours: Double
    public var entryCount: Int
}

public struct PeriodHours: Identifiable, Hashable, Sendable {
    public var start: CalendarDate
    public var hours: Double
    public var billableHours: Double

    public var id: CalendarDate { start }
}

public struct EntryAnalytics: Sendable {
    public let entries: [TrackedEntry]
    private let now: Date

    public init(_ entries: [TrackedEntry], asOf now: Date = Date()) {
        self.entries = entries
        self.now = now
    }

    private func hours(_ entry: TrackedEntry) -> Double { entry.hours(asOf: now) }

    public var totalHours: Double { entries.reduce(0) { $0 + hours($1) } }
    public var billableHours: Double { entries.filter(\.isBillable).reduce(0) { $0 + hours($1) } }
    public var nonBillableHours: Double { totalHours - billableHours }
    public var entryCount: Int { entries.count }

    public var billableShare: Double {
        let total = totalHours
        return total > 0 ? billableHours / total : 0
    }

    public var activeDays: Int { Set(entries.map(\.spentDate)).count }

    public var averagePerActiveDay: Double {
        activeDays > 0 ? totalHours / Double(activeDays) : 0
    }

    // MARK: - Groupings

    public func byProject() -> [HoursBucket] {
        grouped { entry in
            ("p\(entry.project.id)", entry.project.name, entry.client?.name)
        }
    }

    public func byClient() -> [HoursBucket] {
        grouped { entry in
            ("c\(entry.client?.id ?? 0)", entry.client?.name ?? "No client", nil)
        }
    }

    public func byTask() -> [HoursBucket] {
        grouped { entry in
            ("t\(entry.task.id)", entry.task.name, nil)
        }
    }

    private func grouped(by key: (TrackedEntry) -> (id: String, name: String, detail: String?)) -> [HoursBucket] {
        var buckets: [String: HoursBucket] = [:]
        for entry in entries {
            let (id, name, detail) = key(entry)
            var bucket = buckets[id] ?? HoursBucket(
                id: id, name: name, detail: detail, hours: 0, billableHours: 0, entryCount: 0
            )
            let worked = hours(entry)
            bucket.hours += worked
            if entry.isBillable { bucket.billableHours += worked }
            bucket.entryCount += 1
            buckets[id] = bucket
        }
        return buckets.values.sorted { ($1.hours, $0.name) < ($0.hours, $1.name) }
    }

    // MARK: - Over time

    public func byDay() -> [PeriodHours] {
        periods(step: { $0.adding(days: 1) }, floor: { $0 })
    }

    public func byWeek(weekStart: Weekday) -> [PeriodHours] {
        periods(step: { $0.adding(days: 7) }, floor: { $0.startOfWeek(weekStart: weekStart) })
    }

    public func byMonth() -> [PeriodHours] {
        periods(
            step: { date in
                let index = date.year * 12 + (date.month - 1) + 1
                return CalendarDate(year: index / 12, month: index % 12 + 1, day: 1)
            },
            floor: { CalendarDate(year: $0.year, month: $0.month, day: 1) }
        )
    }

    /// Every period from the first to the last entry, including the empty ones: a chart
    /// that skipped them would draw a quiet fortnight as if it were one busy day.
    private func periods(
        step: (CalendarDate) -> CalendarDate,
        floor: (CalendarDate) -> CalendarDate
    ) -> [PeriodHours] {
        guard let first = entries.map(\.spentDate).min(), let last = entries.map(\.spentDate).max() else { return [] }

        var totals: [CalendarDate: (all: Double, billable: Double)] = [:]
        for entry in entries {
            let start = floor(entry.spentDate)
            let worked = hours(entry)
            totals[start, default: (0, 0)].all += worked
            if entry.isBillable { totals[start, default: (0, 0)].billable += worked }
        }

        var result: [PeriodHours] = []
        var cursor = floor(first)
        let end = floor(last)
        while cursor <= end {
            let sum = totals[cursor] ?? (0, 0)
            result.append(PeriodHours(start: cursor, hours: sum.all, billableHours: sum.billable))
            cursor = step(cursor)
        }
        return result
    }
}
