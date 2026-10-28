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
}
