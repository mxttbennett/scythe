import ScytheCore
import SwiftUI

/// A compact look at how the current day sits alongside the previous day, week, and month.
struct TimeSummaryPopover: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker

    let format: HoursFormat
    let weekStart: Weekday
    @State private var summary: TimeSummarySnapshot?

    var body: some View {
        let now = tracker.now
        VStack(alignment: .leading, spacing: 0) {
            Text("Time summary")
                .uiFont(.title3)
                .uiPadding(.horizontal, 14)
                .uiPadding(.vertical, 10)

            Divider()

            if let summary {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 14 * uiScale
                ) {
                    ForEach(summary.periods) { period in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(period.title)
                                .uiFont(.callout)
                                .foregroundStyle(GlassInk.secondary)
                            Text(summary.hours(for: period, at: now).formattedHours(format))
                                .uiFont(.largeTitle, monospacedDigit: true)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .uiPadding(14)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 116)
            }
        }
        .uiFrame(width: 350)
        .onAppear(perform: refresh)
        .onChange(of: history.entriesVersion) { refresh() }
        .onChange(of: tracker.entries) { refresh() }
        .onChange(of: tracker.day) { refresh() }
    }

    private func refresh() {
        let visibleDay = tracker.entries
        let entries = history.entries.filter { $0.spentDate != tracker.day } + visibleDay
        summary = TimeSummarySnapshot(entries: entries, weekStart: weekStart, asOf: tracker.now)
    }
}

private struct TimeSummaryPeriod: Identifiable {
    let id: String
    let title: String
    let start: CalendarDate
    let end: CalendarDate

    func contains(_ date: CalendarDate) -> Bool { start <= date && date <= end }
}

/// Stores history totals once, while allowing active timers to keep ticking in the popover.
private struct TimeSummarySnapshot {
    private struct RunningTimer {
        let date: CalendarDate
        let startedAt: Date
    }

    let periods: [TimeSummaryPeriod]
    private let capturedAt: Date
    private let totals: [String: Double]
    private let runningTimers: [RunningTimer]

    init(entries: [TrackedEntry], weekStart: Weekday, asOf now: Date) {
        let today = CalendarDate(now)
        let yesterday = today.adding(days: -1)
        let monthStart = CalendarDate(year: today.year, month: today.month, day: 1)
        periods = [
            TimeSummaryPeriod(id: "today", title: "Hours today", start: today, end: today),
            TimeSummaryPeriod(id: "yesterday", title: "Hours yesterday", start: yesterday, end: yesterday),
            TimeSummaryPeriod(
                id: "week", title: "Hours this week", start: today.startOfWeek(weekStart: weekStart), end: today
            ),
            TimeSummaryPeriod(id: "month", title: "Hours this month", start: monthStart, end: today)
        ]
        capturedAt = now

        var totals = Dictionary(uniqueKeysWithValues: periods.map { ($0.id, 0.0) })
        var runningTimers: [RunningTimer] = []
        for entry in entries {
            let hours = entry.hours(asOf: now)
            for period in periods where period.contains(entry.spentDate) {
                totals[period.id, default: 0] += hours
            }
            if entry.isRunning, let startedAt = entry.timerStartedAt {
                runningTimers.append(RunningTimer(date: entry.spentDate, startedAt: startedAt))
            }
        }
        self.totals = totals
        self.runningTimers = runningTimers
    }

    func hours(for period: TimeSummaryPeriod, at now: Date) -> Double {
        let liveElapsed = runningTimers.reduce(0.0) { total, timer in
            guard period.contains(timer.date) else { return total }
            let start = max(capturedAt, timer.startedAt)
            return total + max(0, now.timeIntervalSince(start)) / 3600
        }
        return totals[period.id, default: 0] + liveElapsed
    }
}
