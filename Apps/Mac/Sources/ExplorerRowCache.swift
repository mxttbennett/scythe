import ScytheCore
import SwiftUI

/// The explorer's sorted and progressively filtered rows.
///
/// The table's body runs for every click, hover and selection. Filtering and sorting two years
/// of entries took 1 to 44 ms depending on the query. Keep client-level results so project and
/// task changes only filter the smaller eligible set. A plain class, not observed: reading it
/// from `body` must not trigger another body.
@MainActor
final class ExplorerRowCache {
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

    func rows(
        entries: [TrackedEntry],
        version: Int,
        index: SearchIndex?,
        filter: EntryFilter,
        weekStart: Weekday,
        today: CalendarDate,
        order: [KeyPathComparator<TrackedEntry>]
    ) -> [TrackedEntry] {
        let wanted = Key(version: version, filter: filter, weekStart: weekStart, today: today, order: order)
        if wanted == key { return cached }
        computeCount += 1
        let wantedSort = SortKey(version: version, order: order)
        if wantedSort != sortKey {
            sortedEntries = entries.sorted(using: order)
            sortKey = wantedSort
            baseKey = nil
            projectKey = nil
        }

        let wantedBase = BaseKey(
            version: version, period: filter.period, text: filter.text, clientIDs: filter.clientIDs,
            billable: filter.billable, weekStart: weekStart, today: today, order: order
        )
        if wantedBase != baseKey {
            var baseFilter = filter
            baseFilter.projectIDs = []
            baseFilter.taskIDs = []
            baseRows = baseFilter.apply(to: sortedEntries, today: today, weekStart: weekStart, index: index)
            baseKey = wantedBase
            projectKey = nil
        }

        let wantedProjects = ProjectKey(base: wantedBase, projectIDs: filter.projectIDs)
        if wantedProjects != projectKey {
            projectRows = filter.projectIDs.isEmpty
                ? baseRows
                : baseRows.filter { filter.projectIDs.contains($0.project.id) }
            projectKey = wantedProjects
        }

        // The base and project stages are already in table order, so selecting or
        // clearing tasks only examines rows that survived those parent filters.
        cached = filter.taskIDs.isEmpty
            ? projectRows
            : projectRows.filter { filter.taskIDs.contains($0.task.id) }
        key = wanted
        return cached
    }
}
