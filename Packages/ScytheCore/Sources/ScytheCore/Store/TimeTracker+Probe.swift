import Foundation

extension TimeTracker {
    /// How long the visible day may go unchecked before the app asks Harvest
    /// uninvited, or nil when it should not ask at all.
    ///
    /// Every user action already syncs on the spot; the probe exists to catch
    /// changes made elsewhere, such as the web timesheet or a phone. A running or
    /// recently stopped timer means someone is working, so the day is checked every
    /// 10 seconds on the mains or a battery alike, and an idle machine every minute.
    /// Low Power Mode is the user saying to spend nothing: the probe stops and
    /// syncing goes back to being purely event-driven.
    nonisolated static func probeInterval(for activity: Activity, on power: PowerState) -> TimeInterval? {
        switch (power, activity) {
        case (.lowPower, _): nil
        case (_, .idle): 60
        case (_, _): 10
        }
    }

    /// Never slower than the probe, so a probe is not held up by the tick that
    /// checks for it. A running timer already ticks every 5 seconds for its display.
    nonisolated static func tickInterval(isRunning: Bool, probe: TimeInterval?) -> Duration {
        let display: Duration = isRunning ? .seconds(5) : .seconds(30)
        guard let probe else { return display }
        return min(display, .seconds(probe))
    }

    /// A tick can land a hair before the interval is up; without the slack that probe waits a whole extra tick.
    nonisolated static func probeIsDue(elapsed: TimeInterval, interval: TimeInterval) -> Bool {
        elapsed >= interval - 1
    }
}
