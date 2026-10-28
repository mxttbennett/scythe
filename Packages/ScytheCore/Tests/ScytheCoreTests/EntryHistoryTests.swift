import Foundation
import Testing
@testable import ScytheCore

@Suite("Entry history")
struct EntryHistoryTests {
    private let today = CalendarDate(year: 2026, month: 10, day: 27)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ id: Int64, on date: CalendarDate, hours: Double = 1, notes: String? = nil) -> TrackedEntry {
        TrackedEntry(
            id: .server(id),
            project: Reference(id: 1, name: "Online Store"),
            task: Reference(id: 2, name: "Programming"),
            notes: notes, spentDate: date, bankedHours: hours, isRunning: false
        )
    }

    /// Records what it was asked for and answers from a fixed list.
    private actor Fetches {
        struct Call: Equatable {
            var from: CalendarDate
            var to: CalendarDate?
            var updatedSince: Date?
        }
        private(set) var calls: [Call] = []
        var answers: [[TrackedEntry]]

        init(_ answers: [[TrackedEntry]]) { self.answers = answers }

        func next(from: CalendarDate, to: CalendarDate?, updatedSince: Date?) -> [TrackedEntry] {
            calls.append(Call(from: from, to: to, updatedSince: updatedSince))
            return answers.isEmpty ? [] : answers.removeFirst()
        }
    }

    private func fetcher(_ fetches: Fetches) -> HistoryFetcher {
        HistoryFetcher { from, to, updatedSince in
            await fetches.next(from: from, to: to, updatedSince: updatedSince)
        }
    }

    @Test("the first refresh backfills two years in one request")
    func firstRefreshBackfills() async throws {
        // Arrange
        let fetches = Fetches([[entry(1, on: today)]])
        var history = EntryHistory()

        // Act
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now)

        // Assert
        let calls = await fetches.calls
        #expect(calls == [.init(from: today.adding(days: -730), to: nil, updatedSince: nil)])
        #expect(history.entries.count == 1)
        #expect(history.syncedAt == now)
    }

    @Test("a later refresh asks only for changes and the recent window")
    func laterRefreshIsIncremental() async throws {
        // Arrange
        let fetches = Fetches([[entry(1, on: today)], [], []])
        var history = EntryHistory()
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now)
        let later = now.addingTimeInterval(3600)

        // Act
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: later)

        // Assert
        let calls = await fetches.calls
        #expect(calls.count == 3)
        #expect(calls[1].updatedSince == now.addingTimeInterval(-300))
        #expect(calls[2] == .init(from: today.adding(days: -60), to: nil, updatedSince: nil))
    }

    @Test("an entry deleted on Harvest disappears from the recent window")
    func deletionIsReconciled() async throws {
        // Arrange
        let yesterday = today.adding(days: -1)
        let fetches = Fetches([[entry(1, on: today), entry(2, on: yesterday)], [], [entry(1, on: today)]])
        var history = EntryHistory()
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now)

        // Act
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now.addingTimeInterval(60))

        // Assert
        #expect(history.entries.map(\.id) == [.server(1)])
    }

    @Test("an entry edited long ago is updated in place")
    func oldEditIsMerged() async throws {
        // Arrange
        let old = today.adding(days: -300)
        let fetches = Fetches([[entry(1, on: old, hours: 1)], [entry(1, on: old, hours: 3)], []])
        var history = EntryHistory()
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now)

        // Act
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now.addingTimeInterval(60))

        // Assert
        #expect(history.entries.map(\.bankedHours) == [3])
    }

    @Test("a different user starts from an empty history")
    func otherUserResets() async throws {
        // Arrange
        let fetches = Fetches([[entry(1, on: today)], [entry(9, on: today)]])
        var history = EntryHistory()
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now)

        // Act
        try await history.refresh(userID: 8, using: fetcher(fetches), today: today, now: now)

        // Assert
        #expect(history.entries.map(\.id) == [.server(9)])
    }

    @Test("a failed fetch leaves the history as it was")
    func failureKeepsHistory() async throws {
        // Arrange
        let fetches = Fetches([[entry(1, on: today)]])
        var history = EntryHistory()
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now)
        struct Boom: Error {}
        let failing = HistoryFetcher { _, _, _ in throw Boom() }

        // Act
        await #expect(throws: Boom.self) {
            try await history.refresh(userID: 7, using: failing, today: today, now: now.addingTimeInterval(60))
        }

        // Assert
        #expect(history.entries.map(\.id) == [.server(1)])
        #expect(history.syncedAt == now)
    }

    @Test("a cache saved before entries carried their link is rebuilt")
    func oldCacheIsRebuilt() async throws {
        // Arrange
        var saved = EntryHistory()
        try await saved.refresh(userID: 7, using: fetcher(Fetches([[entry(1, on: today)]])), today: today, now: now)
        var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        fields["version"] = nil
        var history = try JSONDecoder().decode(EntryHistory.self, from: JSONSerialization.data(withJSONObject: fields))
        let fetches = Fetches([[entry(1, on: today)]])

        // Act
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now.addingTimeInterval(60))

        // Assert
        let calls = await fetches.calls
        #expect(calls == [.init(from: today.adding(days: -730), to: nil, updatedSince: nil)])
    }

    @Test("a cache saved before entries carried their created time is rebuilt")
    func previousVersionCacheIsRebuilt() async throws {
        // Arrange
        var saved = EntryHistory()
        try await saved.refresh(userID: 7, using: fetcher(Fetches([[entry(1, on: today)]])), today: today, now: now)
        var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        fields["version"] = 2
        var history = try JSONDecoder().decode(EntryHistory.self, from: JSONSerialization.data(withJSONObject: fields))
        let fetches = Fetches([[entry(1, on: today)]])

        // Act
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now.addingTimeInterval(60))

        // Assert
        let calls = await fetches.calls
        #expect(calls == [.init(from: today.adding(days: -730), to: nil, updatedSince: nil)])
    }

    @Test("history survives a round trip through the store")
    func storeRoundTrip() async throws {
        // Arrange
        let fetches = Fetches([[entry(1, on: today, notes: "COG-1553: review")]])
        var history = EntryHistory()
        try await history.refresh(userID: 7, using: fetcher(fetches), today: today, now: now)
        let url = FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString).json")
        let store = HistoryStore(fileURL: url)

        // Act
        try store.save(history)
        let loaded = store.load()

        // Assert
        #expect(loaded?.entries.first?.notes == "COG-1553: review")
        #expect(loaded?.userID == 7)
    }
}
