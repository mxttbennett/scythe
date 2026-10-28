import Foundation

/// How the history cache reads Harvest, so it can be tested without a network.
public struct HistoryFetcher: Sendable {
    public var fetch: @Sendable (_ from: CalendarDate, _ to: CalendarDate?, _ updatedSince: Date?) async throws -> [TrackedEntry]

    public init(
        fetch: @escaping @Sendable (_ from: CalendarDate, _ to: CalendarDate?, _ updatedSince: Date?) async throws -> [TrackedEntry]
    ) {
        self.fetch = fetch
    }
}

/// Every entry the user has logged in the last two years, kept locally so the desktop
/// window can filter and total them without a request.
///
/// Whole-file persistence is fine at this size, for the reason `SnapshotStore` gives:
/// a busy year of one person's entries is well under a megabyte, and a file that is
/// replaced in one write cannot be half-updated.
public struct EntryHistory: Codable, Sendable {
    public static let backfillDays = 730
    /// Harvest reports an edit through `updated_since` but not a delete, so this much of
    /// the recent past is replaced wholesale on every refresh to notice entries that went.
    public static let reconcileDays = 60
    private static let overlap: TimeInterval = 300
    /// Raised when entries gain data an older cache file lacks, so that file is rebuilt.
    private static let currentVersion = 3

    private var version: Int?
    public private(set) var entries: [TrackedEntry] = []
    public private(set) var coveredFrom: CalendarDate?
    public private(set) var syncedAt: Date?
    public private(set) var userID: Int?

    public init() {}

    public mutating func refresh(
        userID: Int,
        using fetcher: HistoryFetcher,
        today: CalendarDate = .today(),
        now: Date = Date()
    ) async throws {
        // Work on a copy: a request that fails halfway must not leave a half-merged cache.
        var next = self.userID == userID && version == Self.currentVersion ? self : EntryHistory()
        next.userID = userID
        next.version = Self.currentVersion

        let start = today.adding(days: -Self.backfillDays)
        if let covered = next.coveredFrom, covered <= start, let since = next.syncedAt {
            let changed = try await fetcher.fetch(covered, nil, since.addingTimeInterval(-Self.overlap))
            next.merge(changed, replacing: nil)

            let windowStart = today.adding(days: -Self.reconcileDays)
            let recent = try await fetcher.fetch(windowStart, nil, nil)
            next.merge(recent, replacing: windowStart...CalendarDate.distantFuture)
        } else {
            let everything = try await fetcher.fetch(start, nil, nil)
            next.entries = []
            next.merge(everything, replacing: nil)
            next.coveredFrom = start
        }

        next.syncedAt = now
        self = next
    }

    /// Reflects a change the user just made, ahead of Harvest confirming it.
    public mutating func apply(_ id: TrackedEntry.ID, _ change: (inout TrackedEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    /// Folds in what the tracker already holds for its day, so the history follows the menu bar without asking Harvest again.
    public mutating func absorb(_ live: [TrackedEntry], on day: CalendarDate) {
        let liveIDs = Set(live.map(\.id))
        entries.removeAll { $0.spentDate == day && !liveIDs.contains($0.id) }
        merge(live, replacing: nil)
    }

    public mutating func remove(_ id: TrackedEntry.ID) {
        entries.removeAll { $0.id == id }
    }

    private mutating func merge(_ fetched: [TrackedEntry], replacing window: ClosedRange<CalendarDate>?) {
        if let window {
            entries.removeAll { window.contains($0.spentDate) }
        }
        var index: [TrackedEntry.ID: Int] = [:]
        for (position, entry) in entries.enumerated() { index[entry.id] = position }
        for entry in fetched {
            if let position = index[entry.id] {
                entries[position] = entry
            } else {
                index[entry.id] = entries.count
                entries.append(entry)
            }
        }
        entries.sort { ($0.spentDate, $0.updatedAt) > ($1.spentDate, $1.updatedAt) }
    }
}

private extension CalendarDate {
    static let distantFuture = CalendarDate(year: 9999, month: 12, day: 31)
}

/// Reads and writes the history as a single JSON file.
public struct HistoryStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(appName: String = "Scythe") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let directory = base.appending(path: appName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appending(path: "history.json")
    }

    /// Nil rather than a throw: a missing or unreadable cache just means starting over.
    public func load() -> EntryHistory? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(EntryHistory.self, from: data)
    }

    public func save(_ history: EntryHistory) throws {
        try JSONEncoder().encode(history).write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
