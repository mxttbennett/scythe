import Foundation
import ScytheCore

enum StatusItemAccessibility {
    static func label(for activity: TimeTracker.Activity) -> String {
        guard let entry = activity.entry else { return "Scythe, nothing tracked" }
        return "Scythe, \(entry.task.name), \(entry.target.projectLabel)"
    }

    static func value(
        for activity: TimeTracker.Activity,
        style: StatusItemStyle,
        isToday: Bool,
        totalHours: Double,
        now: Date
    ) -> String {
        guard let entry = activity.entry else { return "no timer running" }
        let duration = spokenDuration(for: entry.hours(asOf: now))
        let state = "\(duration), \(entry.isRunning ? "timer running" : "paused")"
        guard style == .stacked, isToday else { return state }
        return "\(state), \(spokenDuration(for: totalHours)) total today"
    }

    private static func spokenDuration(for hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let hourCount = total / 60
        let minuteCount = total % 60
        switch (hourCount, minuteCount) {
        case (0, let minutes):
            return "\(minutes.formatted()) minute\(minutes == 1 ? "" : "s")"
        case (let hours, 0):
            return "\(hours.formatted()) hour\(hours == 1 ? "" : "s")"
        case (let hours, let minutes):
            return "\(hours.formatted()) hour\(hours == 1 ? "" : "s") \(minutes.formatted()) minute\(minutes == 1 ? "" : "s")"
        }
    }
}
