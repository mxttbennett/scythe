import Foundation
import ScytheCore
import Testing
@testable import Scythe

@Suite("Dock badge")
struct DockBadgeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(bankedHours: Double = 0, runningFor seconds: TimeInterval? = nil) -> TrackedEntry {
        TrackedEntry(
            id: .server(1), project: Reference(id: 1, name: "Online Store"),
            task: Reference(id: 2, name: "Programming"), spentDate: .today(),
            bankedHours: bankedHours, isRunning: seconds != nil,
            timerStartedAt: seconds.map { now.addingTimeInterval(-$0) }
        )
    }

    @Test("a running timer badges the minutes on its entry's clock")
    func showsMinutes() {
        // Arrange
        let running = entry(bankedHours: 0.5, runningFor: 10 * 60)

        // Act
        let label = DockBadge.label(for: .running(running), at: now, enabled: true)

        // Assert
        #expect(label == "40")
    }

    @Test("minutes round to the nearest, as the entry list does")
    func roundsToNearestMinute() {
        // Arrange
        let justUnder = entry(runningFor: 29)
        let justOver = entry(runningFor: 31)

        // Act & Assert
        #expect(DockBadge.label(for: .running(justUnder), at: now, enabled: true) == "0")
        #expect(DockBadge.label(for: .running(justOver), at: now, enabled: true) == "1")
    }

    @Test("past an hour the badge keeps counting minutes")
    func countsPastAnHour() {
        // Arrange
        let running = entry(bankedHours: 1, runningFor: 65 * 60)

        // Act
        let label = DockBadge.label(for: .running(running), at: now, enabled: true)

        // Assert
        #expect(label == "125")
    }

    @Test("a paused entry shows no badge")
    func pausedShowsNothing() {
        // Arrange
        let paused = entry(bankedHours: 0.5)

        // Act
        let label = DockBadge.label(for: .recent(paused), at: now, enabled: true)

        // Assert
        #expect(label == nil)
    }

    @Test("with nothing tracked there is no badge")
    func idleShowsNothing() {
        // Act & Assert
        #expect(DockBadge.label(for: .idle, at: now, enabled: true) == nil)
    }

    @Test("a running timer shows no badge until the user turns it on")
    func disabledShowsNothing() {
        // Arrange
        let running = entry(bankedHours: 0.5, runningFor: 10 * 60)

        // Act
        let label = DockBadge.label(for: .running(running), at: now, enabled: false)

        // Assert
        #expect(label == nil)
    }
}
