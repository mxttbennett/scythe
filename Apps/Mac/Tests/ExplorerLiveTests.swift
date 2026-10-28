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

    @Test("average per day uses tracked dates and rounds to two decimals")
    func averagePerDayUsesTrackedDates() async throws {
        // Arrange
        let tracker = await makeTracker()
        var first = try #require(tracker.entries.first)
        first.bankedHours = 2.25
        var sameDay = first
        sameDay.id = .server(9_999_001)
        var nextDay = first
        nextDay.id = .server(9_999_002)
        nextDay.spentDate = first.spentDate.adding(days: 1)
        let rows = [first, sameDay, nextDay]

        // Act
        let average = ExplorerSummary.averagePerDayLabel(totalHours: 10.987, spentDates: rows.map(\.spentDate))
        let emptyAverage = ExplorerSummary.averagePerDayLabel(totalHours: 0, spentDates: [])

        // Assert
        #expect(average == "5.49 avg/day")
        #expect(emptyAverage == "0.00 avg/day")
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

    @Test("unwrapped notes keep every row the same height")
    func unwrappedNotesKeepRowHeight() {
        // Act
        let short = height(of: NotesCell(text: "1:1 w/ Devin", wraps: false))
        let long = height(of: NotesCell(text: Self.longNote, wraps: false))

        // Assert
        #expect(short == long)
    }

    @Test("wrapped notes show in full, however many lines that takes")
    func wrappedNotesGrowWithTheirText() {
        // Act
        let short = height(of: NotesCell(text: "1:1 w/ Devin", wraps: true))
        let twoLines = height(of: NotesCell(text: String(repeating: "Set the default tax rate. ", count: 12), wraps: true))
        let manyLines = height(of: NotesCell(text: Self.longNote, wraps: true))

        // Assert
        #expect(twoLines > short)
        #expect(manyLines > twoLines)
    }

    @Test("the explorer follows the wrap setting")
    func explorerFollowsWrapSetting() async throws {
        // Arrange
        let tracker = await makeTracker()
        let history = HistoryModel(tracker: tracker, store: nil, fetcher: DemoHistory.fetcher, userID: 1)
        await history.refresh()
        var entry = try #require(tracker.entries.first)
        entry.id = .server(9_999_001)
        entry.notes = Self.longNote
        history.absorb(tracker.entries + [entry], on: tracker.day)
        defer { UserDefaults.standard.removeObject(forKey: "explorerWrapNotes") }

        // Act
        UserDefaults.standard.set(true, forKey: "explorerWrapNotes")
        let wrapped = try await explorerImage(history: history, tracker: tracker)
        UserDefaults.standard.set(false, forKey: "explorerWrapNotes")
        let oneLine = try await explorerImage(history: history, tracker: tracker)

        // Assert
        #expect(wrapped != oneLine)
    }

    private func explorerImage(history: HistoryModel, tracker: TimeTracker) async throws -> Data {
        let hosting = NSHostingView(
            rootView: ExplorerView()
                .environment(history)
                .environment(tracker)
                .environment(DesktopState(store: nil))
                .environment(EntryDateFormatPreference())
                .frame(width: 1100, height: 430)
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 1100, height: 430)
        let window = NSWindow(
            contentRect: hosting.frame.offsetBy(dx: -30_000, dy: -30_000),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(900))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private static let longNote = String(repeating: "Set the default tax rate to six decimals. ", count: 12)

    private func height(of view: some View) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 240))
        return renderer.nsImage?.size.height ?? 0
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
