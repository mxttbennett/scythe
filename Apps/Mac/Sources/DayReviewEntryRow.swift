import ScytheCore
import SwiftUI

struct DayReviewEntryRow: View {
    let entry: TrackedEntry
    let format: HoursFormat
    let start: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.project.name)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    if let client = entry.client {
                        Text(client.name)
                        Text("·")
                    }
                    Text(entry.task.name)
                }
                .font(.callout)
                .foregroundStyle(GlassInk.secondary)
                if let notes = entry.notes, !notes.isEmpty {
                    Text(NoteLinks.attributed(notes))
                        .font(.callout)
                        .foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 8) {
                LiveReviewHours(entries: [entry], format: format, style: .title3.weight(.medium))
                Button(action: start) {
                    Label(entry.isRunning ? "Stop" : "Start", systemImage: entry.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .tint(entry.isRunning ? .red : .accentColor)
                .disabled(entry.isLocked)
                .help(entry.isLocked ? "This entry is locked" : entry.isRunning ? "Stop this timer" : "Start this timer")
                Button("Edit Entry", systemImage: "pencil", action: edit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Edit entry")
                    .disabled(entry.isLocked)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(entry.isRunning ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

struct LiveReviewHours: View {
    @Environment(TimeTracker.self) private var tracker

    let format: HoursFormat
    let style: Font
    var tint: AnyShapeStyle = AnyShapeStyle(.primary)
    var accessibilityPrefix: String? = nil

    private let bankedHours: Double
    private let runningEntries: [TrackedEntry]

    init(
        entries: [TrackedEntry],
        format: HoursFormat,
        style: Font,
        tint: AnyShapeStyle = AnyShapeStyle(.primary),
        accessibilityPrefix: String? = nil
    ) {
        self.format = format
        self.style = style
        self.tint = tint
        self.accessibilityPrefix = accessibilityPrefix
        bankedHours = entries.reduce(0) { $0 + $1.bankedHours }
        runningEntries = entries.filter(\.isRunning)
    }

    var body: some View {
        let now = runningEntries.isEmpty ? nil : tracker.now
        let total = runningEntries.reduce(bankedHours) { value, entry in
            guard let now, let startedAt = entry.timerStartedAt else { return value }
            return value + max(0, now.timeIntervalSince(startedAt)) / 3600
        }
        Text(total.formattedHours(format))
            .font(style.monospacedDigit())
            .foregroundStyle(tint)
            .contentTransition(.numericText())
            .accessibilityLabel(
                accessibilityPrefix.map { "\($0), \(total.formattedHours(format))" }
                    ?? total.formattedHours(format)
            )
    }
}
