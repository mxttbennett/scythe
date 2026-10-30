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
    ) async -> [Int64] {
        let request = ExplorerRowsRequest(
            version: version, filter: filter, weekStart: .monday, today: today ?? self.today,
            order: order ?? byDate
        )
        let snapshot = await cache.rows(entries: entries, index: nil, request: request)
        return snapshot.entries.compactMap { $0.id.serverID }
    }

    @Test("the rows are filtered and sorted")
    func filtersAndSorts() async {
        // Act
        let result = await rows(ExplorerRowCache())

        // Assert
        #expect(result == [2, 3, 1])
    }

    @Test("asking again with the same inputs does not recompute")
    func sameInputsReuse() async {
        // Arrange
        let cache = ExplorerRowCache()

        // Act
        _ = await rows(cache)
        _ = await rows(cache)

        // Assert
        let computeCount = await cache.computeCount
        #expect(computeCount == 1)
    }

    @Test("a new version of the entries recomputes")
    func versionChangeRecomputes() async {
        // Arrange
        let cache = ExplorerRowCache()
        _ = await rows(cache, version: 1)

        // Act
        _ = await rows(cache, version: 2)

        // Assert
        let computeCount = await cache.computeCount
        #expect(computeCount == 2)
    }

    @Test("a changed filter recomputes and applies")
    func filterChangeRecomputes() async {
        // Arrange
        let cache = ExplorerRowCache()
        _ = await rows(cache)
        var filter = EntryFilter()
        filter.text = "second"

        // Act
        let result = await rows(cache, filter: filter)

        // Assert
        #expect(result == [2])
        let computeCount = await cache.computeCount
        #expect(computeCount == 2)
    }

    @Test("a changed sort order recomputes and applies")
    func orderChangeRecomputes() async {
        // Arrange
        let cache = ExplorerRowCache()
        _ = await rows(cache)

        // Act
        let result = await rows(cache, order: [KeyPathComparator(\TrackedEntry.spentDate, order: .forward)])

        // Assert
        #expect(result == [1, 3, 2])
        let computeCount = await cache.computeCount
        #expect(computeCount == 2)
    }

    @Test("a new day recomputes, because relative periods move with it")
    func newDayRecomputes() async {
        // Arrange
        let cache = ExplorerRowCache()
        _ = await rows(cache)

        // Act
        _ = await rows(cache, today: today.adding(days: 1))

        // Assert
        let computeCount = await cache.computeCount
        #expect(computeCount == 2)
    }
}
