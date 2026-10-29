import ScytheCore
import SwiftUI

/// One week as a grid, editable in place: a cell with a single entry changes its hours,
/// and an empty cell logs a new one.
struct TimesheetView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker

    @State private var weekStart: CalendarDate?
    /// Rows the user added for a project and task that have nothing logged this week yet.
    @State private var addedTargets: [TimerTarget] = []

    private var currentWeekStart: CalendarDate {
        weekStart ?? CalendarDate.today().startOfWeek(weekStart: history.weekStart)
    }

    var body: some View {
        let start = currentWeekStart
        let sheet = Timesheet.build(from: history.entries, weekStart: start)
        let format = history.hoursFormat

        VStack(spacing: 0) {
            header(start: start, sheet: sheet, format: format)
            Divider()
            GeometryReader { geometry in
                let totalWidth: CGFloat = 64
                let spacing: CGFloat = 6
                let gridWidth = max(0, geometry.size.width - 32 - spacing * 8)
                let labelWidth = min(280, max(128, gridWidth - 7 * 72 - totalWidth))
                let dayWidth = min(72, max(48, (gridWidth - labelWidth - totalWidth) / 7))

                ScrollView {
                    Grid(alignment: .trailing, horizontalSpacing: spacing, verticalSpacing: 6) {
                        dayHeaders(sheet, labelWidth: labelWidth, dayWidth: dayWidth, totalWidth: totalWidth)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(sheet.rows) { row in
                            GridRow {
                                rowLabel(row.project, row.task, row.client, width: labelWidth)
                                ForEach(0..<7, id: \.self) { day in
                                    HoursCell(
                                        entries: row.entriesByDay[day],
                                        hours: row.hoursByDay[day],
                                        target: TimerTarget(project: row.project, task: row.task, client: row.client),
                                        date: sheet.days[day],
                                        format: format,
                                        width: dayWidth
                                    )
                                }
                                totalText(row.total, format: format, width: totalWidth)
                            }
                        }
                        ForEach(addedRows(excluding: sheet)) { target in
                            GridRow {
                                rowLabel(target.project, target.task, target.client, width: labelWidth)
                                ForEach(0..<7, id: \.self) { day in
                                    HoursCell(
                                        entries: [], hours: 0, target: target,
                                        date: sheet.days[day], format: format, width: dayWidth
                                    )
                                }
                                totalText(0, format: format, width: totalWidth)
                            }
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        GridRow {
                            Text("Total")
                                .font(.callout.weight(.semibold))
                                .frame(width: labelWidth, alignment: .leading)
                                .gridColumnAlignment(.leading)
                            ForEach(0..<7, id: \.self) { day in
                                totalText(sheet.dayTotals[day], format: format, bold: true, width: dayWidth)
                            }
                            totalText(sheet.total, format: format, bold: true, width: totalWidth)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .toolbar { ToolbarItemGroup { RefreshButton() } }
    }

    // MARK: - Pieces

    private func header(start: CalendarDate, sheet: Timesheet, format: HoursFormat) -> some View {
        HStack(spacing: 10) {
            Button { weekStart = start.adding(days: -7) } label: { Image(systemName: "chevron.left") }
                .help("Previous week")
            Button { weekStart = start.adding(days: 7) } label: { Image(systemName: "chevron.right") }
                .help("Next week")
            Text("\(start.startOfDay().formatted(.dateTime.month(.abbreviated).day())) – \(sheet.days[6].startOfDay().formatted(.dateTime.month(.abbreviated).day().year()))")
                .font(.headline)
            Button("This Week") { weekStart = nil }
                .disabled(weekStart == nil)
            Spacer()
            addMenu(sheet: sheet)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func addMenu(sheet: Timesheet) -> some View {
        let existing = Set(sheet.rows.map(\.id) + addedTargets.map(\.id))
        let candidates = Self.orderedUniqueTargets(tracker.frequentTargets + tracker.targets, excluding: existing)

        return Menu {
            ForEach(candidates.prefix(40)) { target in
                Button("\(target.projectLabel) — \(target.task.name)") { addedTargets.append(target) }
            }
        } label: {
            Label("Add Row", systemImage: "plus")
        }
        .fixedSize()
        .disabled(candidates.isEmpty)
    }

    static func orderedUniqueTargets(_ targets: [TimerTarget], excluding existing: Set<String> = []) -> [TimerTarget] {
        var seen = Set<String>()
        return targets.filter { !existing.contains($0.id) && seen.insert($0.id).inserted }
    }

    private func addedRows(excluding sheet: Timesheet) -> [TimerTarget] {
        let existing = Set(sheet.rows.map(\.id))
        return addedTargets.filter { !existing.contains($0.id) }
    }

    private func dayHeaders(_ sheet: Timesheet, labelWidth: CGFloat, dayWidth: CGFloat, totalWidth: CGFloat) -> some View {
        GridRow {
            Color.clear.frame(width: labelWidth, height: 1).gridColumnAlignment(.leading)
            ForEach(sheet.days.indices, id: \.self) { index in
                let date = sheet.days[index]
                VStack(spacing: 0) {
                    Text(date.startOfDay(), format: .dateTime.weekday(.abbreviated))
                        .font(.caption).foregroundStyle(GlassInk.secondary)
                    Text(date.startOfDay(), format: .dateTime.day())
                        .font(.callout.weight(date == .today() ? .bold : .regular))
                        .foregroundStyle(date == .today() ? Color.accentColor : .primary)
                }
                .frame(width: dayWidth)
            }
            Text("Total").font(.caption).foregroundStyle(GlassInk.secondary).frame(width: totalWidth)
        }
    }

    private func rowLabel(_ project: Reference, _ task: Reference, _ client: Reference?, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(project.name).font(.callout).lineLimit(1)
            Text("\(client.map { "\($0.name) · " } ?? "")\(task.name)")
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .gridColumnAlignment(.leading)
    }

    private func totalText(_ hours: Double, format: HoursFormat, bold: Bool = false, width: CGFloat) -> some View {
        Text(hours == 0 ? "–" : hours.formattedHours(format))
            .font(.callout.weight(bold ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(hours == 0 ? GlassInk.tertiary : AnyShapeStyle(.primary))
            .frame(width: width, alignment: .trailing)
    }
}

/// One day of one project and task. It edits when there is at most one entry behind it;
/// several entries make the total a sum that has no single number to change.
private struct HoursCell: View {
    @Environment(HistoryModel.self) private var history

    let entries: [TrackedEntry]
    let hours: Double
    let target: TimerTarget
    let date: CalendarDate
    let format: HoursFormat
    let width: CGFloat

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var isEditable: Bool { entries.count <= 1 && entries.first?.isLocked != true && entries.first?.isRunning != true }
    private var isRunning: Bool { entries.contains(where: \.isRunning) }
    private var shown: String { hours == 0 ? "" : hours.formattedHours(format) }

    var body: some View {
        Group {
            if isEditable {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            } else {
                Text(shown)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(isRunning ? AnyShapeStyle(Color.accentColor) : GlassInk.secondary)
                    .accessibilityLabel(isRunning ? "Timer running, \(shown)" : shown)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 7)
                    .help(helpText)
            }
        }
        .frame(width: width)
        .onAppear { text = shown }
        .onChange(of: shown) { _, newValue in if !isFocused { text = newValue } }
    }

    private func commit() {
        guard text != shown else { return }
        guard let value = Double.hours(parsing: text), value > 0 else {
            text = shown
            return
        }
        let entry = entries.first
        let target = target
        let date = date
        Task {
            if let entry {
                await history.updateHours(entry, to: value)
            } else {
                await history.logHours(value, against: target, on: date)
            }
        }
    }

    private var helpText: String {
        if entries.count > 1, isRunning {
            return "\(entries.count) entries, including a running timer. Stop it in the menu bar panel. Edit entries in the explorer."
        }
        if entries.count > 1 { return "\(entries.count) entries. Edit them in the explorer." }
        if isRunning { return "Timer running. Stop it in the menu bar panel before changing this time." }
        return "This entry can’t be changed here."
    }
}
