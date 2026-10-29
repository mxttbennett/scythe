import ScytheCore
import SwiftUI

/// A table cell's hours. Only a running entry reads the tracker's clock, so a tick redraws that one cell and not the table.
struct LiveHours: View {
    let tracker: TimeTracker
    let entry: TrackedEntry
    let format: HoursFormat

    var body: some View {
        HStack(spacing: 4) {
            if entry.isRunning {
                Image(systemName: "timer")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Timer running")
                    .help("Timer running")
            }
            Text((entry.isRunning ? entry.hours(asOf: tracker.now) : entry.bankedHours).formattedHours(format))
                .monospacedDigit()
        }
    }
}

/// The explorer's totals. They read the tracker's clock only while a running entry is in the rows.
struct ExplorerSummary: View {
    @Environment(HistoryModel.self) private var history
    let rows: [TrackedEntry]
    let format: HoursFormat

    static func averagePerDayLabel(totalHours: Double, spentDates: [CalendarDate]) -> String {
        let trackedDays = Set(spentDates).count
        let average = trackedDays == 0 ? 0 : totalHours / Double(trackedDays)
        return "\(average.formatted(.number.precision(.fractionLength(2)))) avg/day"
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("\(rows.count.formatted()) \(rows.count == 1 ? "entry" : "entries")")
            ExplorerSummaryHours(rows: rows, format: format)
            Spacer()
            if let failure = history.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if let syncedAt = history.syncedAt {
                Text("Updated \(syncedAt, format: .relative(presentation: .named))")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(GlassInk.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct ExplorerSummaryHours: View {
    @Environment(TimeTracker.self) private var tracker
    private let baseHours: Double
    private let baseBillableHours: Double
    private let runningEntries: [TrackedEntry]
    private let spentDates: [CalendarDate]
    private let format: HoursFormat

    init(rows: [TrackedEntry], format: HoursFormat) {
        var hours = 0.0
        var billableHours = 0.0
        var running: [TrackedEntry] = []
        for entry in rows {
            hours += entry.bankedHours
            if entry.isBillable { billableHours += entry.bankedHours }
            if entry.isRunning { running.append(entry) }
        }
        baseHours = hours
        baseBillableHours = billableHours
        runningEntries = running
        spentDates = rows.map(\.spentDate)
        self.format = format
    }

    var body: some View {
        let now = runningEntries.isEmpty ? nil : tracker.now
        let totals = runningEntries.reduce(into: (total: baseHours, billable: baseBillableHours)) { totals, entry in
            guard let now, let startedAt = entry.timerStartedAt else { return }
            let elapsed = max(0, now.timeIntervalSince(startedAt)) / 3600
            totals.total += elapsed
            if entry.isBillable { totals.billable += elapsed }
        }
        let share = totals.total > 0 ? totals.billable / totals.total : 0
        return Group {
            Text("\(totals.total.formattedHours(format)) total")
            Text("\(totals.billable.formattedHours(format)) billable (\(share.formatted(.percent.precision(.fractionLength(0)))))")
            Text(ExplorerSummary.averagePerDayLabel(totalHours: totals.total, spentDates: spentDates))
        }
    }
}

/// A table cell's notes: in full across as many lines as they need, or cut to one line so every row stays the same height.
struct NotesCell: View {
    let text: String
    let wraps: Bool

    var body: some View {
        Text(NoteLinks.attributed(text))
            .lineLimit(wraps ? 3 : 1)
            .foregroundStyle(GlassInk.secondary)
    }
}
