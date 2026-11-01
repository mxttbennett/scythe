import Foundation
import ScytheCore
import Testing
@testable import Scythe

@Suite("History persistence")
@MainActor
struct HistoryModelPersistenceTests {
    private func tracker() -> TimeTracker {
        TimeTracker(
            client: HarvestClient(credentials: .init(accountID: "0", token: "t"), transport: DemoAccount()),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.tests-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: URL.temporaryDirectory.appending(path: "hm-snap-\(UUID().uuidString).json")),
            queue: MutationQueue(fileURL: URL.temporaryDirectory.appending(path: "hm-queue-\(UUID().uuidString).json"))
        )
    }

    /// What Harvest currently says the entry's notes are; a refresh may ask more than once.
    private actor Harvest {
        var notes: String
        init(_ notes: String) { self.notes = notes }
        func say(_ notes: String) { self.notes = notes }
        func entries() -> [TrackedEntry] {
            [TrackedEntry(
                id: .server(1),
                project: Reference(id: 1, name: "Online Store"),
                task: Reference(id: 2, name: "Programming"),
                notes: notes, spentDate: .today(), bankedHours: 1, isRunning: false
            )]
        }
    }

    private func model(file: URL, harvest: Harvest) -> HistoryModel {
        let fetcher = HistoryFetcher { _, _, _ in await harvest.entries() }
        return HistoryModel(tracker: tracker(), store: HistoryStore(fileURL: file), fetcher: fetcher, userID: 7)
    }

    @Test("a refresh is written to the history file")
    func refreshIsSaved() async {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "hm-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let model = model(file: file, harvest: Harvest("saved"))

        // Act
        await model.refresh()
        await model.waitForWrites()

        // Assert
        #expect(HistoryStore(fileURL: file).load()?.entries.first?.notes == "saved")
    }

    @Test("when refreshes come quickly, the file ends up holding the last one")
    func lastRefreshWins() async {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "hm-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let harvest = Harvest("old")
        let model = model(file: file, harvest: harvest)

        // Act
        await model.refresh()
        await harvest.say("new")
        await model.refresh()
        await harvest.say("newest")
        await model.refresh()
        await model.waitForWrites()

        // Assert
        #expect(HistoryStore(fileURL: file).load()?.entries.first?.notes == "newest")
    }

    @Test("every publish moves the entries' version on")
    func versionAdvances() async {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "hm-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let harvest = Harvest("a")
        let model = model(file: file, harvest: harvest)
        let before = model.entriesVersion

        // Act
        await model.refresh()
        let afterFirst = model.entriesVersion
        await harvest.say("b")
        await model.refresh()

        // Assert
        #expect(afterFirst > before)
        #expect(model.entriesVersion > afterFirst)
    }

    @Test("opening the window does not wait for the history file to be read")
    func cacheLoadsOffTheMainThread() async {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "hm-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var cached = EntryHistory()
        try? await cached.refresh(userID: 7, using: HistoryFetcher { _, _, _ in await Harvest("cached").entries() })
        try? HistoryStore(fileURL: file).save(cached)

        // Act
        let model = model(file: file, harvest: Harvest("ignored"))
        let entriesRightAway = model.entries.count
        let loadingRightAway = model.isRefreshing
        await model.waitForCache()

        // Assert
        #expect(entriesRightAway == 0)
        #expect(loadingRightAway)
        #expect(model.entries.first?.notes == "cached")
        #expect(!model.isRefreshing)
    }

    @Test("a refresh waits for the cache, so it updates what was saved rather than starting over")
    func refreshFollowsCacheLoad() async {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "hm-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var cached = EntryHistory()
        try? await cached.refresh(userID: 7, using: HistoryFetcher { _, _, _ in await Harvest("cached").entries() })
        try? HistoryStore(fileURL: file).save(cached)
        let calls = Calls()
        let fetcher = HistoryFetcher { from, _, since in
            await calls.record(since)
            return await Harvest("fresh").entries()
        }
        let model = HistoryModel(tracker: tracker(), store: HistoryStore(fileURL: file), fetcher: fetcher, userID: 7)

        // Act
        await model.refresh()

        // Assert
        #expect(await calls.sawIncrementalFetch)
        #expect(model.entries.first?.notes == "fresh")
    }

    private actor Calls {
        private var sinces: [Date?] = []
        func record(_ since: Date?) { sinces.append(since) }
        var sawIncrementalFetch: Bool { sinces.contains { $0 != nil } }
    }

    @Test("filter menus offer only what goes with the chosen clients and projects")
    func filterOptionsFollowFacets() async {
        // Arrange
        func entry(_ id: Int64, client: Int, project: Int, task: Int) -> TrackedEntry {
            TrackedEntry(
                id: .server(id), project: Reference(id: project, name: "Project \(project)"),
                task: Reference(id: task, name: "Task \(task)"), client: Reference(id: client, name: "Client \(client)"),
                spentDate: .today(), bankedHours: 1, isRunning: false
            )
        }
        let entries = [
            entry(1, client: 30, project: 10, task: 20), entry(2, client: 30, project: 10, task: 21),
            entry(3, client: 31, project: 11, task: 20), entry(4, client: 31, project: 12, task: 22),
        ]
        let model = HistoryModel(
            tracker: tracker(), store: nil, fetcher: HistoryFetcher { _, _, _ in entries }, userID: 7
        )

        // Act
        await model.refresh()

        // Assert
        #expect(model.projects.map(\.id) == [10, 11, 12])
        #expect(model.clients.map(\.id) == [30, 31])
        #expect(model.tasks.map(\.id) == [20, 21, 22])
        #expect(model.projectIDsByClient == [30: [10], 31: [11, 12]])
        #expect(model.taskIDsByClient == [30: [20, 21], 31: [20, 22]])
        #expect(model.taskIDsByProject == [10: [20, 21], 11: [20], 12: [22]])
        #expect(model.projectOptions(forClientIDs: []).map(\.id) == [10, 11, 12])
        #expect(model.projectOptions(forClientIDs: [31]).map(\.id) == [11, 12])
        #expect(model.taskOptions(forClientIDs: [], projectIDs: []).map(\.id) == [20, 21, 22])
        #expect(model.taskOptions(forClientIDs: [31], projectIDs: []).map(\.id) == [20, 22])
        #expect(model.taskOptions(forClientIDs: [], projectIDs: [10]).map(\.id) == [20, 21])
        #expect(model.taskOptions(forClientIDs: [31], projectIDs: [11]).map(\.id) == [20])
        #expect(model.projectIDs(forClientIDs: []) == [10, 11, 12])
        #expect(model.projectIDs(forClientIDs: [30]) == [10])
        #expect(model.taskIDs(forClientIDs: [], projectIDs: []) == [20, 21, 22])
        #expect(model.taskIDs(forClientIDs: [31], projectIDs: []) == [20, 22])
        #expect(model.taskIDs(forClientIDs: [], projectIDs: [12]) == [22])
        #expect(model.taskIDs(forClientIDs: [31], projectIDs: [11]) == [20])
    }
}
