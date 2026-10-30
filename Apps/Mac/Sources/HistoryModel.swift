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
    private(set) var projectIDsByClient: [Int: Set<Int>] = [:]
    private(set) var taskIDsByClient: [Int: Set<Int>] = [:]
    private(set) var taskIDsByProject: [Int: Set<Int>] = [:]
    private var projectsByID: [Int: Reference] = [:]
    private var tasksByID: [Int: Reference] = [:]
    private var allProjectIDs: Set<Int> = []
    private var allTaskIDs: Set<Int> = []
    private(set) var isRefreshing = false
    private(set) var syncedAt: Date?
    private(set) var failure: String?
    /// Moves on with every publish, so a view can tell cheaply that `entries` changed.
    private(set) var entriesVersion = 0
    private(set) var searchIndex = SearchIndex([])

    private var history: EntryHistory
    private let store: HistoryStore?
    private let tracker: TimeTracker
    private let fetcher: HistoryFetcher?
    private let userID: Int?
    private var writeTask: Task<Void, Never>?

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

    func projectOptions(forClientIDs clientIDs: Set<Int>) -> [Reference] {
        guard !clientIDs.isEmpty else { return projects }
        let allowed = clientIDs.reduce(into: Set<Int>()) { result, clientID in
            result.formUnion(projectIDsByClient[clientID] ?? [])
        }
        return allowed.compactMap { projectsByID[$0] }.sorted(by: Self.referenceOrder)
    }

    func taskOptions(forClientIDs clientIDs: Set<Int>, projectIDs: Set<Int>) -> [Reference] {
        let byClient = clientIDs.reduce(into: Set<Int>()) { result, clientID in
            result.formUnion(taskIDsByClient[clientID] ?? [])
        }
        let byProject = projectIDs.reduce(into: Set<Int>()) { result, projectID in
            result.formUnion(taskIDsByProject[projectID] ?? [])
        }
        let allowed: Set<Int>
        switch (clientIDs.isEmpty, projectIDs.isEmpty) {
        case (false, false): allowed = byClient.intersection(byProject)
        case (false, true): allowed = byClient
        case (true, false): allowed = byProject
        case (true, true): return tasks
        }
        return allowed.compactMap { tasksByID[$0] }.sorted(by: Self.referenceOrder)
    }

    func projectIDs(forClientIDs clientIDs: Set<Int>) -> Set<Int> {
        guard !clientIDs.isEmpty else { return allProjectIDs }
        return clientIDs.reduce(into: Set<Int>()) { result, clientID in
            result.formUnion(projectIDsByClient[clientID] ?? [])
        }
    }

    func taskIDs(forClientIDs clientIDs: Set<Int>, projectIDs: Set<Int>) -> Set<Int> {
        let byClient = clientIDs.reduce(into: Set<Int>()) { result, clientID in
            result.formUnion(taskIDsByClient[clientID] ?? [])
        }
        let byProject = projectIDs.reduce(into: Set<Int>()) { result, projectID in
            result.formUnion(taskIDsByProject[projectID] ?? [])
        }
        return switch (clientIDs.isEmpty, projectIDs.isEmpty) {
        case (false, false): byClient.intersection(byProject)
        case (false, true): byClient
        case (true, false): byProject
        case (true, true): allTaskIDs
        }
    }

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
            save(next)
        } catch {
            Self.log.error("history refresh failed: \(error.localizedDescription, privacy: .public)")
            failure = error.localizedDescription
        }
    }

    /// Takes the tracker's day as it stands, so a timer started or stopped from the menu bar shows up here.
    func absorb(_ live: [TrackedEntry], on day: CalendarDate) {
        history.absorb(live, on: day)
        publish()
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

    func updateTarget(_ entry: TrackedEntry, to target: TimerTarget) async {
        history.apply(entry.id) {
            $0.project = target.project
            $0.task = target.task
            $0.client = target.client
            $0.isPending = true
        }
        publish()
        await tracker.updateTarget(entry, to: target)
        await settle()
    }

    func updateEntry(
        _ entry: TrackedEntry, notes: String?, hours: Double?, target: TimerTarget?, spentDate: CalendarDate? = nil
    ) async {
        guard notes != nil || hours != nil || target != nil || spentDate != nil else { return }
        guard let current = await tracker.currentEntry(matching: entry.id) else { return }
        guard !current.isLocked else { return }
        history.apply(current.id) {
            if let notes { $0.notes = notes }
            if let target {
                $0.project = target.project
                $0.task = target.task
                $0.client = target.client
            }
            if let hours { $0.bankedHours = hours }
            if let spentDate { $0.spentDate = spentDate }
            $0.isPending = true
        }
        publish()
        await tracker.updateEntry(current, notes: notes, hours: hours, target: target, spentDate: spentDate)
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

    /// Written in the background, one write after another: encoding two years of entries took about 23 ms,
    /// which the main thread felt after every edit.
    private func save(_ history: EntryHistory) {
        guard let store else { return }
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            try? store.save(history)
        }
    }

    func waitForWrites() async {
        await writeTask?.value
    }

    private func publish() {
        entries = history.entries
        entriesVersion += 1
        searchIndex = SearchIndex(entries)
        syncedAt = history.syncedAt
        projects = Self.distinct(entries.map(\.project))
        clients = Self.distinct(entries.compactMap(\.client))
        tasks = Self.distinct(entries.map(\.task))
        projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        allProjectIDs = Set(projectsByID.keys)
        allTaskIDs = Set(tasksByID.keys)
        var nextProjectIDsByClient: [Int: Set<Int>] = [:]
        var nextTaskIDsByClient: [Int: Set<Int>] = [:]
        var nextTaskIDsByProject: [Int: Set<Int>] = [:]
        for entry in entries {
            nextTaskIDsByProject[entry.project.id, default: []].insert(entry.task.id)
            if let clientID = entry.client?.id {
                nextProjectIDsByClient[clientID, default: []].insert(entry.project.id)
                nextTaskIDsByClient[clientID, default: []].insert(entry.task.id)
            }
        }
        projectIDsByClient = nextProjectIDsByClient
        taskIDsByClient = nextTaskIDsByClient
        taskIDsByProject = nextTaskIDsByProject
    }

    private static func distinct(_ references: [Reference]) -> [Reference] {
        Dictionary(references.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted(by: referenceOrder)
    }

    private static func referenceOrder(_ lhs: Reference, _ rhs: Reference) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
