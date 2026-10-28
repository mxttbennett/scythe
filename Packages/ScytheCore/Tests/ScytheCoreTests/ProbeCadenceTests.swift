import Foundation
import Testing
@testable import ScytheCore

@Suite("Probe cadence")
struct ProbeCadenceTests {
    private var running: TimeTracker.Activity {
        .running(
            TrackedEntry(
                id: .server(1), project: Reference(id: 1, name: "P"),
                task: Reference(id: 2, name: "T"), spentDate: .today(),
                bankedHours: 0, isRunning: true, timerStartedAt: Date()
            )
        )
    }

    private var recent: TimeTracker.Activity {
        .recent(
            TrackedEntry(
                id: .server(1), project: Reference(id: 1, name: "P"),
                task: Reference(id: 2, name: "T"), spentDate: .today(),
                bankedHours: 0.5, isRunning: false
            )
        )
    }

    @Test("Low Power Mode stops the probe entirely")
    func lowPowerStopsProbing() {
        // Act & Assert
        #expect(TimeTracker.probeInterval(for: running, on: .lowPower) == nil)
        #expect(TimeTracker.probeInterval(for: .idle, on: .lowPower) == nil)
    }

    @Test("a running or recently stopped timer probes every 10 seconds, on the mains or a battery")
    func activeProbesEveryTenSeconds() {
        for power in [PowerState.pluggedIn, .battery] {
            // Act & Assert
            #expect(TimeTracker.probeInterval(for: running, on: power) == 10)
            #expect(TimeTracker.probeInterval(for: recent, on: power) == 10)
        }
    }

    @Test("an idle machine probes every 60 seconds, on the mains or a battery")
    func idleProbesEveryMinute() {
        for power in [PowerState.pluggedIn, .battery] {
            // Act & Assert
            #expect(TimeTracker.probeInterval(for: .idle, on: power) == 60)
        }
    }

    @Test("the clock ticks at least as often as the probe is due, so it is never late by a whole tick")
    func tickFollowsProbe() {
        // Act & Assert
        #expect(TimeTracker.tickInterval(isRunning: true, probe: 10) == .seconds(5))
        #expect(TimeTracker.tickInterval(isRunning: false, probe: 10) == .seconds(10))
        #expect(TimeTracker.tickInterval(isRunning: false, probe: 60) == .seconds(30))
        #expect(TimeTracker.tickInterval(isRunning: false, probe: nil) == .seconds(30))
        #expect(TimeTracker.tickInterval(isRunning: true, probe: nil) == .seconds(5))
    }

    @Test("a probe is due a second early, so a tick that lands a hair short does not wait a whole extra tick")
    func dueWithSlack() {
        // Act & Assert
        #expect(TimeTracker.probeIsDue(elapsed: 9.2, interval: 10))
        #expect(TimeTracker.probeIsDue(elapsed: 59.5, interval: 60))
        #expect(!TimeTracker.probeIsDue(elapsed: 8.5, interval: 10))
        #expect(!TimeTracker.probeIsDue(elapsed: 5, interval: 10))
    }
}
