import Foundation
import ScytheCore
import Testing
@testable import Scythe

/// The status item is built with the history model, so its `init` is main-thread time before the menu bar responds.
@Suite("Startup performance")
@MainActor
struct StartupPerformanceTests {
    private func writeHistory(entryCount: Int, to file: URL) async throws {
        var history = EntryHistory()
        let today = CalendarDate.today()
        let entries = (0..<entryCount).map { index in
            TrackedEntry(
                id: .server(Int64(1_000 + index)),
                project: Reference(id: index % 40, name: "Project \(index % 40)"),
                task: Reference(id: index % 8, name: "Task \(index % 8)"),
                client: Reference(id: index % 6, name: "Client \(index % 6)"),
                notes: "Reviewed the checkout flow for ticket \(index)",
                spentDate: today.adding(days: -(index / 8)), bankedHours: 1.25, isRunning: false
            )
        }
        try await history.refresh(userID: 7, using: HistoryFetcher { _, _, _ in entries }, today: today)
        try HistoryStore(fileURL: file).save(history)
    }

    @Test("building the history model over two years of entries blocks the main thread for under 25 ms")
    func initDoesNotDecodeTheCache() async throws {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "startup-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try await writeHistory(entryCount: 5000, to: file)
        let tracker = TimeTracker(
            client: HarvestClient(credentials: .init(accountID: "0", token: "t"), transport: DemoAccount()),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.tests-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: URL.temporaryDirectory.appending(path: "startup-snap-\(UUID().uuidString).json")),
            queue: MutationQueue(fileURL: URL.temporaryDirectory.appending(path: "startup-queue-\(UUID().uuidString).json"))
        )
        let store = HistoryStore(fileURL: file)

        // Act
        let elapsed = ContinuousClock().measure {
            _ = HistoryModel(tracker: tracker, store: store)
        }

        // Assert
        let milliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("KPI startup.history-model-init-main-ms=\(milliseconds)")
        #expect(milliseconds < 25, "init blocked the main thread for \(milliseconds) ms")
    }
}
