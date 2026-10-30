import ScytheCore
import SwiftUI

struct DayReviewModePicker: View {
    @Binding var isDayReview: Bool

    var body: some View {
        Picker("View", selection: $isDayReview) {
            Text("Day").tag(false)
            Text("Week Review").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Menu bar view")
    }
}

struct DayReviewWeekStrip: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker

    private var days: [CalendarDate] {
        let start = tracker.day.startOfWeek(weekStart: history.weekStart)
        return (0..<7).map { start.adding(days: $0) }
    }

    private var entriesByDate: [CalendarDate: [TrackedEntry]] {
        let daySet = Set(days)
        var entries = Dictionary(
            uniqueKeysWithValues: history.entries
                .filter { daySet.contains($0.spentDate) }
                .map { ($0.id, $0) }
        )
        for entry in tracker.entries where daySet.contains(entry.spentDate) {
            entries[entry.id] = entry
        }
        return Dictionary(grouping: entries.values, by: \.spentDate)
    }

    var body: some View {
        let entriesByDate = self.entriesByDate
        HStack(spacing: 3 * uiScale) {
            ForEach(days, id: \.self) { date in
                let selected = date == tracker.day
                let today = date == .today()
                let dayEntries = entriesByDate[date] ?? []
                Button {
                    Task { await tracker.selectDay(date) }
                } label: {
                    VStack(spacing: 2 * uiScale) {
                        Text(date.startOfDay(), format: .dateTime.weekday(.abbreviated))
                            .uiFont(.caption2)
                            .textCase(.uppercase)
                            .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.78)) : AnyShapeStyle(GlassInk.secondary))
                            .accessibilityHidden(true)
                        Text(date.startOfDay(), format: .dateTime.day())
                            .uiFont(.callout, monospacedDigit: true)
                            .fontWeight(selected || today ? .semibold : .regular)
                            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(today ? Color.accentColor : .primary))
                            .accessibilityHidden(true)
                        LiveReviewHours(
                            entries: dayEntries,
                            format: history.hoursFormat,
                            style: .caption2,
                            tint: selected ? AnyShapeStyle(.white.opacity(0.88)) : AnyShapeStyle(GlassInk.secondary),
                            accessibilityPrefix: date.startOfDay().formatted(.dateTime.weekday(.wide).month(.wide).day())
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 58 * uiScale)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8 * uiScale)
                                .fill(Color.accentColor)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(date.startOfDay().formatted(.dateTime.weekday(.wide).month(.wide).day()))
            }
        }
        .padding(.vertical, 2 * uiScale)
    }
}
