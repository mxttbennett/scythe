import Foundation
import ScytheCore
import SwiftUI
import Testing
@testable import Scythe

@Suite("Explorer row cache")
@MainActor
struct ExplorerRowCacheTests {
    private let today = CalendarDate(year: 2026, month: 10, day: 27)

    private func entry(_ id: Int64, on day: Int, notes: String) -> TrackedEntry {
        TrackedEntry(
            id: .server(id),
            project: Reference(id: 1, name: "Online Store"),
            task: Reference(id: 2, name: "Programming"),
            notes: notes,
            spentDate: CalendarDate(year: 2026, month: 10, day: day),
            bankedHours: 1, isRunning: false
        )
    }

    private var entries: [TrackedEntry] {
        [entry(1, on: 25, notes: "first"), entry(2, on: 27, notes: "second"), entry(3, on: 26, notes: "third")]
    }

    private let byDate = [KeyPathComparator(\TrackedEntry.spentDate, order: .reverse)]

    private func rows(
        _ cache: ExplorerRowCache, version: Int = 1, filter: EntryFilter = EntryFilter(),
        order: [KeyPathComparator<TrackedEntry>]? = nil, today: CalendarDate? = nil
    ) -> [Int64] {
        cache.rows(
            entries: entries, version: version, index: nil, filter: filter,
            weekStart: .monday, today: today ?? self.today, order: order ?? byDate
        ).compactMap { $0.id.serverID }
    }

    @Test("the rows are filtered and sorted")
    func filtersAndSorts() {
        // Act
        let result = rows(ExplorerRowCache())

        // Assert
        #expect(result == [2, 3, 1])
    }

    @Test("asking again with the same inputs does not recompute")
    func sameInputsReuse() {
        // Arrange
        let cache = ExplorerRowCache()

        // Act
        _ = rows(cache)
        _ = rows(cache)

        // Assert
        #expect(cache.computeCount == 1)
    }

    @Test("a new version of the entries recomputes")
    func versionChangeRecomputes() {
        // Arrange
        let cache = ExplorerRowCache()
        _ = rows(cache, version: 1)

        // Act
        _ = rows(cache, version: 2)

        // Assert
        #expect(cache.computeCount == 2)
    }

    @Test("a changed filter recomputes and applies")
    func filterChangeRecomputes() {
        // Arrange
        let cache = ExplorerRowCache()
        _ = rows(cache)
        var filter = EntryFilter()
        filter.text = "second"

        // Act
        let result = rows(cache, filter: filter)

        // Assert
        #expect(result == [2])
        #expect(cache.computeCount == 2)
    }

    @Test("a changed sort order recomputes and applies")
    func orderChangeRecomputes() {
        // Arrange
        let cache = ExplorerRowCache()
        _ = rows(cache)

        // Act
        let result = rows(cache, order: [KeyPathComparator(\TrackedEntry.spentDate, order: .forward)])

        // Assert
        #expect(result == [1, 3, 2])
        #expect(cache.computeCount == 2)
    }

    @Test("a new day recomputes, because relative periods move with it")
    func newDayRecomputes() {
        // Arrange
        let cache = ExplorerRowCache()
        _ = rows(cache)

        // Act
        _ = rows(cache, today: today.adding(days: 1))

        // Assert
        #expect(cache.computeCount == 2)
    }
}
