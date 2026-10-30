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
    private var requestID = 0
    private(set) var computeCount = 0
    private(set) var tableGeneration = 0

    func rows(
        entries: [TrackedEntry],
        index: SearchIndex?,
        request: ExplorerRowsRequest
    ) async -> ExplorerRowsSnapshot {
        requestID += 1
        let requestID = self.requestID
        if Task.isCancelled { return snapshot }
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
        let nextProjectRows: [TrackedEntry]
        if wantedProjects != projectKey {
            if request.filter.projectIDs.isEmpty {
                nextProjectRows = baseRows
            } else if let filtered = await matching(baseRows, requestID: requestID, where: {
                request.filter.projectIDs.contains($0.project.id)
            }) {
                guard !Task.isCancelled, self.requestID == requestID else { return snapshot }
                nextProjectRows = filtered
            } else {
                return snapshot
            }
            projectRows = nextProjectRows
            projectKey = wantedProjects
        } else {
            nextProjectRows = projectRows
        }

        // The base and project stages are already in table order, so selecting or
        // clearing tasks only examines rows that survived those parent filters.
        let nextRows: [TrackedEntry]
        if request.filter.taskIDs.isEmpty {
            nextRows = nextProjectRows
        } else if let filtered = await matching(nextProjectRows, requestID: requestID, where: {
            request.filter.taskIDs.contains($0.task.id)
        }) {
            nextRows = filtered
        } else {
            return snapshot
        }
        guard !Task.isCancelled, self.requestID == requestID else { return snapshot }
        cached = nextRows
        key = wanted
        return snapshot
    }

    private var snapshot: ExplorerRowsSnapshot {
        ExplorerRowsSnapshot(entries: cached, generation: tableGeneration)
    }

    private func matching(
        _ entries: [TrackedEntry],
        requestID: Int,
        where predicate: (TrackedEntry) -> Bool
    ) async -> [TrackedEntry]? {
        var matches: [TrackedEntry] = []
        matches.reserveCapacity(entries.count)
        for (offset, entry) in entries.enumerated() {
            if offset > 0, offset.isMultiple(of: 256) {
                await Task.yield()
                guard !Task.isCancelled, self.requestID == requestID else { return nil }
            }
            if predicate(entry) { matches.append(entry) }
        }
        return matches
    }
}
