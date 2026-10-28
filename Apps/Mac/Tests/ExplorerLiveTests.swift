import AppKit
import ScytheCore
import SwiftUI
import Testing
@testable import Scythe

@Suite("Explorer live hours")
@MainActor
struct ExplorerLiveTests {
    @Test("a running entry's cell counts up from the tracker's clock")
    func runningCellShowsElapsedTime() async throws {
        // Arrange
        let tracker = await makeTracker()
        var entry = try #require(tracker.entries.first { !$0.isRunning })
        entry.bankedHours = 0.5
        entry.isRunning = true
        entry.timerStartedAt = Date().addingTimeInterval(-3600)

        // Act
        let cell = render(LiveHours(entry: entry, format: HoursFormat(company: tracker.company)).environment(tracker))

        // Assert
        #expect(cell == render(Text("1:30").monospacedDigit()))
        #expect(cell != render(Text("0:30").monospacedDigit()))
    }

    @Test("a stopped entry's cell shows its banked hours")
    func stoppedCellShowsBankedHours() async throws {
        // Arrange
        let tracker = await makeTracker()
        var entry = try #require(tracker.entries.first { !$0.isRunning })
        entry.bankedHours = 0.5

        // Act
        let cell = render(LiveHours(entry: entry, format: HoursFormat(company: tracker.company)).environment(tracker))

        // Assert
        #expect(cell == render(Text("0:30").monospacedDigit()))
    }

    @Test("the summary totals a running entry up to the tracker's clock")
    func summaryCountsRunningEntryLive() async throws {
        // Arrange
        let tracker = await makeTracker()
        let history = HistoryModel(tracker: tracker, store: nil)
        let format = HoursFormat(company: tracker.company)
        var running = try #require(tracker.entries.first { !$0.isRunning })
        running.bankedHours = 0.5
        running.isRunning = true
        running.timerStartedAt = Date().addingTimeInterval(-3600)
        var stopped = running
        stopped.bankedHours = 1.5
        stopped.isRunning = false
        stopped.timerStartedAt = nil
        var banked = running
        banked.isRunning = false
        banked.timerStartedAt = nil

        // Act
        func summary(_ entry: TrackedEntry) -> Data {
            render(ExplorerSummary(rows: [entry], format: format).environment(tracker).environment(history).frame(width: 600))
        }

        // Assert
        #expect(summary(running) == summary(stopped))
        #expect(summary(running) != summary(banked))
    }

    @Test("the history window takes the tracker's day as it stands")
    func historyAbsorbsTrackerDay() async throws {
        // Arrange
        let tracker = await makeTracker()
        let history = HistoryModel(tracker: tracker, store: nil)
        let version = history.entriesVersion

        // Act
        history.absorb(tracker.entries, on: tracker.day)

        // Assert
        #expect(history.entriesVersion == version + 1)
        #expect(Set(history.entries.map(\.id)) == Set(tracker.entries.map(\.id)))
    }

    private func render(_ view: some View) -> Data {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        return renderer.nsImage?.tiffRepresentation ?? Data()
    }

    private func makeTracker() async -> TimeTracker {
        let scratch = URL.temporaryDirectory.appending(path: "scythe-live-\(UUID().uuidString)")
        let tracker = TimeTracker(
            client: HarvestClient(credentials: .init(accountID: "0", token: "none"), transport: DemoAccount()),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.live-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: scratch.appending(path: "snapshot.json")),
            queue: MutationQueue(fileURL: scratch.appending(path: "queue.json"))
        )
        await tracker.sync()
        return tracker
    }
}
