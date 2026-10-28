import Foundation
import Observation
import Testing
@testable import ScytheCore

/// Observation's callback is `@Sendable`, so what it flips has to be a reference the compiler can trust.
private final class Flag: @unchecked Sendable {
    var isSet = false
}

@Suite("Sync and unchanged entries")
@MainActor
struct SyncChangeTests {
    private func account() -> RoutingTransport {
        RoutingTransport([
            RoutingTransport.Route(method: "GET", fragment: "users/me/project_assignments", body: Fixture.projectAssignmentsPage),
            RoutingTransport.Route(method: "GET", fragment: "users/me", body: Fixture.currentUser),
            RoutingTransport.Route(method: "GET", fragment: "company", body: Fixture.company),
            RoutingTransport.Route(method: "PATCH", fragment: "time_entries/", body: Fixture.timeEntry),
            RoutingTransport.Route(method: "GET", fragment: "is_running=true", body: Fixture.timeEntriesPage([])),
            RoutingTransport.Route(method: "GET", fragment: "time_entries", body: Fixture.timeEntriesPage([Fixture.timeEntry])),
        ])
    }

    private func tracker(_ transport: RoutingTransport) async -> (TimeTracker, [URL]) {
        let snapshot = URL.temporaryDirectory.appending(path: "scythe-syncchange-\(UUID().uuidString).json")
        let queue = URL.temporaryDirectory.appending(path: "scythe-syncchange-q-\(UUID().uuidString).json")
        let tracker = TimeTracker(
            client: HarvestClient(credentials: Fixture.credentials, transport: transport, backoffScale: 0),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.tests-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: snapshot),
            queue: MutationQueue(fileURL: queue)
        )
        await tracker.sync()
        return (tracker, [snapshot, queue])
    }

    private func cleanUp(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    @Test("a sync that finds nothing new does not tell the views the entries changed")
    func unchangedSyncIsQuiet() async {
        // Arrange
        let (tracker, files) = await tracker(account())
        defer { cleanUp(files) }
        let notified = Flag()
        withObservationTracking { _ = tracker.entries } onChange: { notified.isSet = true }

        // Act
        await tracker.sync()

        // Assert
        #expect(!notified.isSet)
    }

    @Test("a sync that finds a change does tell the views")
    func changedSyncNotifies() async throws {
        // Arrange
        let (tracker, files) = await tracker(account())
        defer { cleanUp(files) }
        let entry = try #require(tracker.entries.first)
        let notified = Flag()
        withObservationTracking { _ = tracker.entries } onChange: { notified.isSet = true }

        // Act
        await tracker.updateNotes(entry, to: "changed")

        // Assert
        #expect(notified.isSet)
    }
}
