import ScytheCore
import SwiftUI

/// A table cell's hours. Only a running entry reads the tracker's clock, so a tick redraws that one cell and not the table.
struct LiveHours: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TrackedEntry
    let format: HoursFormat

    var body: some View {
        Text((entry.isRunning ? entry.hours(asOf: tracker.now) : entry.bankedHours).formattedHours(format))
            .monospacedDigit()
    }
}

/// The explorer's totals. They read the tracker's clock only while a running entry is in the rows.
struct ExplorerSummary: View {
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker
    let rows: [TrackedEntry]
    let format: HoursFormat

    var body: some View {
        let analytics = rows.contains(where: \.isRunning) ? EntryAnalytics(rows, asOf: tracker.now) : EntryAnalytics(rows)
        HStack(spacing: 16) {
            Text("\(rows.count.formatted()) \(rows.count == 1 ? "entry" : "entries")")
            Text("\(analytics.totalHours.formattedHours(format)) total")
            Text("\(analytics.billableHours.formattedHours(format)) billable (\(analytics.billableShare.formatted(.percent.precision(.fractionLength(0)))))")
            Spacer()
            if let failure = history.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if let syncedAt = history.syncedAt {
                Text("Updated \(syncedAt, format: .relative(presentation: .named))")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A table cell's notes: in full across as many lines as they need, or cut to one line so every row stays the same height.
struct NotesCell: View {
    let text: String
    let wraps: Bool

    var body: some View {
        Text(NoteLinks.attributed(text))
            .lineLimit(wraps ? nil : 1)
            .foregroundStyle(.secondary)
    }
}
