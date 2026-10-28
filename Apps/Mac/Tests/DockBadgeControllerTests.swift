import Foundation
import ScytheCore
import Testing
@testable import Scythe

@Suite("Dock badge controller")
@MainActor
struct DockBadgeControllerTests {
    private final class Sink {
        var labels: [String?] = []
    }

    private func syncedTracker() async -> TimeTracker {
        let tracker = TimeTracker(
            client: HarvestClient(credentials: .init(accountID: "0", token: "t"), transport: DemoAccount()),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.tests-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: URL.temporaryDirectory.appending(path: "badge-snap-\(UUID().uuidString).json")),
            queue: MutationQueue(fileURL: URL.temporaryDirectory.appending(path: "badge-queue-\(UUID().uuidString).json"))
        )
        await tracker.sync()
        return tracker
    }

    private func preference(showing: Bool) -> DockPreference {
        let preference = DockPreference(
            defaults: UserDefaults(suiteName: "DockBadgeControllerTests-\(UUID().uuidString)")!
        )
        preference.showElapsedBadge = showing
        return preference
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test("with the setting on, the running timer's minutes reach the Dock")
    func showsRunningMinutes() async {
        // Arrange
        let sink = Sink()
        let tracker = await syncedTracker()

        // Act
        let controller = DockBadgeController(
            tracker: tracker, preference: preference(showing: true), show: { sink.labels.append($0) }
        )
        await settle()

        // Assert
        #expect(sink.labels == ["90"])
        withExtendedLifetime(controller) {}
    }

    @Test("with the setting off, the Dock is never touched")
    func staysQuietWhenOff() async {
        // Arrange
        let sink = Sink()
        let tracker = await syncedTracker()

        // Act
        let controller = DockBadgeController(
            tracker: tracker, preference: preference(showing: false), show: { sink.labels.append($0) }
        )
        await settle()

        // Assert
        #expect(sink.labels.isEmpty)
        withExtendedLifetime(controller) {}
    }

    @Test("turning the setting on shows the minutes, and turning it off clears them")
    func followsTheSetting() async {
        // Arrange
        let sink = Sink()
        let tracker = await syncedTracker()
        let preference = preference(showing: false)
        let controller = DockBadgeController(tracker: tracker, preference: preference, show: { sink.labels.append($0) })

        // Act
        preference.showElapsedBadge = true
        await settle()
        preference.showElapsedBadge = false
        await settle()

        // Assert
        #expect(sink.labels == ["90", nil])
        withExtendedLifetime(controller) {}
    }
}
