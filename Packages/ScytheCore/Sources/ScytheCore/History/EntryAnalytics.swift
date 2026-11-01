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

    private struct Totals {
        var hours = 0.0
        var billableHours = 0.0
        var activeDays = 0
        var weekdayDays = 0
        var weekendDays = 0
        var weekdayHours = 0.0
        var weekendHours = 0.0
    }

    /// Everything the summary cards read, gathered in the one pass that init makes over the entries.
    private let totals: Totals

    public init(_ entries: [TrackedEntry], asOf now: Date = Date()) {
        self.entries = entries
        self.now = now

        var totals = Totals()
        var days = Set<CalendarDate>(minimumCapacity: min(entries.count, 800))
        for entry in entries {
            let worked = entry.hours(asOf: now)
            totals.hours += worked
            if entry.isBillable { totals.billableHours += worked }
            let isWeekend = entry.spentDate.isWeekend
            if isWeekend { totals.weekendHours += worked } else { totals.weekdayHours += worked }
            if days.insert(entry.spentDate).inserted {
                if isWeekend { totals.weekendDays += 1 } else { totals.weekdayDays += 1 }
            }
        }
        totals.activeDays = days.count
        self.totals = totals
    }

    public var totalHours: Double { totals.hours }
    public var billableHours: Double { totals.billableHours }
    public var nonBillableHours: Double { totals.hours - totals.billableHours }
    public var entryCount: Int { entries.count }

    public var billableShare: Double {
        totals.hours > 0 ? totals.billableHours / totals.hours : 0
    }

    public var activeDays: Int { totals.activeDays }

    public var averagePerActiveDay: Double {
        totals.activeDays > 0 ? totals.hours / Double(totals.activeDays) : 0
    }

    public var weekdayActiveDays: Int { totals.weekdayDays }
    public var weekendActiveDays: Int { totals.weekendDays }

    public var averagePerActiveWeekday: Double {
        totals.weekdayDays > 0 ? totals.weekdayHours / Double(totals.weekdayDays) : 0
    }

    public var averagePerActiveWeekendDay: Double {
        totals.weekendDays > 0 ? totals.weekendHours / Double(totals.weekendDays) : 0
    }

    // MARK: - Groupings

    public func byProject() -> [HoursBucket] {
        grouped(by: { $0.project.id }) { entry in
            HoursBucket(
                id: "p\(entry.project.id)", name: entry.project.name, detail: entry.client?.name,
                hours: 0, billableHours: 0, entryCount: 0
            )
        }
    }

    public func byClient() -> [HoursBucket] {
        grouped(by: { $0.client?.id ?? 0 }) { entry in
            HoursBucket(
                id: "c\(entry.client?.id ?? 0)", name: entry.client?.name ?? "No client", detail: nil,
                hours: 0, billableHours: 0, entryCount: 0
            )
        }
    }

    public func byTask() -> [HoursBucket] {
        grouped(by: { $0.task.id }) { entry in
            HoursBucket(id: "t\(entry.task.id)", name: entry.task.name, detail: nil, hours: 0, billableHours: 0, entryCount: 0)
        }
    }

    /// Keys on the integer so a bucket's text id is built once per bucket, not once per entry.
    private func grouped(by key: (TrackedEntry) -> Int, newBucket: (TrackedEntry) -> HoursBucket) -> [HoursBucket] {
        var buckets: [Int: HoursBucket] = [:]
        for entry in entries {
            let worked = entry.hours(asOf: now)
            let id = key(entry)
            var bucket = buckets.removeValue(forKey: id) ?? newBucket(entry)
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
        guard let first = entries.first else { return [] }
        var earliest = first.spentDate
        var latest = first.spentDate
        for entry in entries {
            if entry.spentDate < earliest { earliest = entry.spentDate }
            if entry.spentDate > latest { latest = entry.spentDate }
        }

        var totals: [CalendarDate: (all: Double, billable: Double)] = [:]
        var lastDate = first.spentDate
        var lastStart = floor(lastDate)
        for entry in entries {
            if entry.spentDate != lastDate {
                lastDate = entry.spentDate
                lastStart = floor(lastDate)
            }
            let worked = entry.hours(asOf: now)
            totals[lastStart, default: (0, 0)].all += worked
            if entry.isBillable { totals[lastStart, default: (0, 0)].billable += worked }
        }

        var result: [PeriodHours] = []
        var cursor = floor(earliest)
        let end = floor(latest)
        while cursor <= end {
            let sum = totals[cursor] ?? (0, 0)
            result.append(PeriodHours(start: cursor, hours: sum.all, billableHours: sum.billable))
            cursor = step(cursor)
        }
        return result
    }
}
