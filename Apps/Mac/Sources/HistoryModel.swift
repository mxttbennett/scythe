import Foundation
import OSLog
import ScytheCore

/// The desktop window's view of every entry, kept in step with Harvest.
///
/// Everything the window shows is read from `entries`, which is in memory, so
/// filtering and totalling never wait on the network. The network only refreshes it.
@MainActor
@Observable
final class HistoryModel {
    private static let log = Logger(subsystem: "com.mxttbennett.scythe", category: "history")

    private(set) var entries: [TrackedEntry] = []
    private(set) var projects: [Reference] = []
    private(set) var clients: [Reference] = []
    private(set) var tasks: [Reference] = []
    private(set) var isRefreshing = false
    private(set) var syncedAt: Date?
    private(set) var failure: String?

    private var history: EntryHistory
    private let store: HistoryStore?
    private let tracker: TimeTracker
    private let fetcher: HistoryFetcher?
    private let userID: Int?

    /// `fetcher` and `userID` replace the tracker's own only for the demo account, which
    /// has no Harvest to ask.
    init(tracker: TimeTracker, store: HistoryStore? = HistoryStore(), fetcher: HistoryFetcher? = nil, userID: Int? = nil) {
        self.tracker = tracker
        self.store = store
        self.fetcher = fetcher
        self.userID = userID
        history = store?.load() ?? EntryHistory()
        publish()
    }

    var weekStart: Weekday { tracker.company?.weekStartDay ?? .monday }
    var hoursFormat: HoursFormat { HoursFormat(company: tracker.company) }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let id: Int
            if let userID {
                id = userID
            } else {
                id = try await tracker.historyUserID()
            }
            var next = history
            try await next.refresh(userID: id, using: fetcher ?? tracker.historyFetcher)
            history = next
            failure = nil
            publish()
            try? store?.save(next)
        } catch {
            Self.log.error("history refresh failed: \(error.localizedDescription, privacy: .public)")
            failure = error.localizedDescription
        }
    }

    // MARK: - Edits

    func updateNotes(_ entry: TrackedEntry, to notes: String) async {
        history.apply(entry.id) {
            $0.notes = notes
            $0.isPending = true
        }
        publish()
        await tracker.updateNotes(entry, to: notes)
        await settle()
    }

    func updateHours(_ entry: TrackedEntry, to hours: Double) async {
        history.apply(entry.id) {
            $0.bankedHours = hours
            $0.isPending = true
        }
        publish()
        await tracker.updateHours(entry, to: hours)
        await settle()
    }

    func delete(_ entry: TrackedEntry) async {
        history.remove(entry.id)
        publish()
        await tracker.delete(entry)
        await settle()
    }

    func logHours(_ hours: Double, against target: TimerTarget, on date: CalendarDate) async {
        await tracker.logHours(hours, against: target, on: date)
        await settle()
    }

    func addEntry(_ draft: EntryDraft) async {
        await tracker.addEntry(against: draft.target, on: draft.date, hours: draft.action.hours, notes: draft.notes)
        await settle()
    }

    /// Lets the queue send what was just queued before reading back, or the read
    /// returns the old value and overwrites the edit on screen.
    private func settle() async {
        await tracker.sync()
        await refresh()
    }

    private func publish() {
        entries = history.entries
        syncedAt = history.syncedAt
        projects = Self.distinct(entries.map(\.project))
        clients = Self.distinct(entries.compactMap(\.client))
        tasks = Self.distinct(entries.map(\.task))
    }

    private static func distinct(_ references: [Reference]) -> [Reference] {
        Dictionary(references.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
