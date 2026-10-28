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

    private var key: Key?
    private var cached: [TrackedEntry] = []
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
        cached = filter.apply(to: entries, today: today, weekStart: weekStart, index: index).sorted(using: order)
        key = wanted
        return cached
    }
}
