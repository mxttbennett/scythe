import ScytheCore
import SwiftUI

struct TimesheetDayReviewView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker

    let week: [CalendarDate]
    @Binding var selectedDay: CalendarDate
    let entries: [TrackedEntry]
    let isRefreshing: Bool
    let format: HoursFormat

    @State private var editingEntry: TrackedEntry?
    @State private var confirmingResume: TrackedEntry?

    private var entriesByDate: [CalendarDate: [TrackedEntry]] {
        Dictionary(grouping: entries, by: \.spentDate)
    }

    private var selectedEntries: [TrackedEntry] {
        (entriesByDate[selectedDay] ?? []).sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDay.startOfDay(), format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title2.weight(.semibold))
                    Text(selectedDay == .today() ? "Today" : selectedDay.startOfDay().formatted(.dateTime.year()))
                        .font(.callout)
                        .foregroundStyle(GlassInk.secondary)
                }
                Spacer()
                LiveReviewHours(entries: entriesByDate[selectedDay] ?? [], format: format, style: .title2.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                ForEach(week.indices, id: \.self) { index in
                    let date = week[index]
                    let isSelected = date == selectedDay
                    let isToday = date == .today()
                    Button {
                        selectedDay = date
                        Task { await tracker.selectDay(date) }
                    } label: {
                        VStack(spacing: 4) {
                            Text(date.startOfDay(), format: .dateTime.weekday(.abbreviated))
                                .font(.caption.weight(.medium))
                                .textCase(.uppercase)
                                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(GlassInk.secondary))
                            Text(date.startOfDay(), format: .dateTime.day())
                                .font(.title3.monospacedDigit().weight(isSelected || isToday ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(isToday ? Color.accentColor : .primary))
                            LiveReviewHours(
                                entries: entriesByDate[date] ?? [],
                                format: format,
                                style: .caption,
                                tint: isSelected ? AnyShapeStyle(.white.opacity(0.88)) : AnyShapeStyle(GlassInk.secondary)
                            )
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9).fill(Color.accentColor)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(date.startOfDay().formatted(.dateTime.weekday(.wide).month(.wide).day())), \((entriesByDate[date] ?? []).reduce(0) { $0 + $1.bankedHours }.formattedHours(format))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            Divider()

            if isRefreshing {
                ProgressView("Loading your history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedEntries.isEmpty {
                ContentUnavailableView {
                    Label("No entries for this day", systemImage: "calendar")
                } description: {
                    Text("Choose another day or use New Entry in the toolbar.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(selectedEntries) { entry in
                            DayReviewEntryRow(
                                entry: entry,
                                format: format,
                                start: { startOrResume(entry) },
                                edit: { editingEntry = entry }
                            )
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(entry: entry, format: format, asOf: tracker.now) { editingEntry = nil }
                .environment(history)
                .environment(tracker)
        }
        .confirmationDialog(
            "Resume this entry?",
            isPresented: Binding(
                get: { confirmingResume != nil },
                set: { if !$0 { confirmingResume = nil } }
            ),
            presenting: confirmingResume
        ) { entry in
            Button("Start on Today") {
                confirmingResume = nil
                Task {
                    await tracker.goToToday()
                    await tracker.start(entry.target, notes: entry.notes)
                }
            }
            Button("Resume on \(entry.spentDate.startOfDay().formatted(.dateTime.month(.abbreviated).day()))") {
                confirmingResume = nil
                Task { await tracker.toggle(entry) }
            }
            Button("Cancel", role: .cancel) { confirmingResume = nil }
        } message: { _ in
            Text("Starting this entry on its original date changes where the time is recorded.")
        }
    }

    private func startOrResume(_ entry: TrackedEntry) {
        guard !entry.isLocked else { return }
        if entry.isRunning {
            Task { await tracker.stop(entry) }
        } else if entry.spentDate != .today() {
            confirmingResume = entry
        } else {
            Task { await tracker.toggle(entry) }
        }
    }
}
