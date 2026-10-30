import ScytheCore
import SwiftUI

struct ExplorerRowsRequest: Equatable, Sendable {
    let version: Int
    let filter: EntryFilter
    let weekStart: Weekday
    let today: CalendarDate
    let order: [KeyPathComparator<TrackedEntry>]
}

struct ExplorerRowsSnapshot: Sendable {
    let entries: [TrackedEntry]
    let generation: Int
}

actor ExplorerRowCache {
    private struct Key: Equatable {
        var version: Int
        var filter: EntryFilter
        var weekStart: Weekday
        var today: CalendarDate
        var order: [KeyPathComparator<TrackedEntry>]
    }

    private struct SortKey: Equatable {
        var version: Int
        var order: [KeyPathComparator<TrackedEntry>]
    }

    private struct BaseKey: Equatable {
        var version: Int
        var period: Period
        var text: String
        var clientIDs: Set<Int>
        var billable: Bool?
        var weekStart: Weekday
        var today: CalendarDate
        var order: [KeyPathComparator<TrackedEntry>]
    }

    private struct ProjectKey: Equatable {
        var base: BaseKey
        var projectIDs: Set<Int>
    }

    private var key: Key?
    private var cached: [TrackedEntry] = []
    private var sortKey: SortKey?
    private var sortedEntries: [TrackedEntry] = []
    private var baseKey: BaseKey?
    private var baseRows: [TrackedEntry] = []
    private var projectKey: ProjectKey?
    private var projectRows: [TrackedEntry] = []
    private(set) var computeCount = 0
    private(set) var tableGeneration = 0

    func rows(
        entries: [TrackedEntry],
        index: SearchIndex?,
        request: ExplorerRowsRequest
    ) -> ExplorerRowsSnapshot {
        if Task.isCancelled { return ExplorerRowsSnapshot(entries: cached, generation: tableGeneration) }
        let wanted = Key(
            version: request.version, filter: request.filter, weekStart: request.weekStart,
            today: request.today, order: request.order
        )
        if wanted == key { return ExplorerRowsSnapshot(entries: cached, generation: tableGeneration) }
        computeCount += 1
        tableGeneration += 1
        let wantedSort = SortKey(version: request.version, order: request.order)
        if wantedSort != sortKey {
            sortedEntries = entries.sorted(using: request.order)
            sortKey = wantedSort
            baseKey = nil
            projectKey = nil
        }

        let wantedBase = BaseKey(
            version: request.version, period: request.filter.period, text: request.filter.text,
            clientIDs: request.filter.clientIDs, billable: request.filter.billable,
            weekStart: request.weekStart, today: request.today, order: request.order
        )
        if wantedBase != baseKey {
            var baseFilter = request.filter
            baseFilter.projectIDs = []
            baseFilter.taskIDs = []
            baseRows = baseFilter.apply(
                to: sortedEntries, today: request.today, weekStart: request.weekStart, index: index
            )
            baseKey = wantedBase
            projectKey = nil
        }

        let wantedProjects = ProjectKey(base: wantedBase, projectIDs: request.filter.projectIDs)
        if wantedProjects != projectKey {
            projectRows = request.filter.projectIDs.isEmpty
                ? baseRows
                : baseRows.filter { request.filter.projectIDs.contains($0.project.id) }
            projectKey = wantedProjects
        }

        // The base and project stages are already in table order, so selecting or
        // clearing tasks only examines rows that survived those parent filters.
        cached = request.filter.taskIDs.isEmpty
            ? projectRows
            : projectRows.filter { request.filter.taskIDs.contains($0.task.id) }
        key = wanted
        return ExplorerRowsSnapshot(entries: cached, generation: tableGeneration)
    }
}
