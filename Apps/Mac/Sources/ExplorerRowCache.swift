import ScytheCore
import SwiftUI

/// The explorer's filtered and sorted rows, kept until something they depend on changes.
///
/// The table's body runs for every click, hover and selection. Filtering and sorting two years
/// of entries took 1 to 44 ms depending on the query, so doing it each time made the explorer
/// stutter. A plain class, not observed: reading it from `body` must not trigger another body.
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

    private var key: Key?
    private var cached: [TrackedEntry] = []
    private var sortKey: SortKey?
    private var sortedEntries: [TrackedEntry] = []
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
        }
        // Filtering preserves the order of its input. Keep history sorted across
        // facet changes so each click doesn't sort the full history again.
        cached = filter.apply(to: sortedEntries, today: today, weekStart: weekStart, index: index)
        key = wanted
        return cached
    }
}
