import SheavesCore
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
            ScrollView {
                Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 6) {
                    dayHeaders(sheet)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(sheet.rows) { row in
                        GridRow {
                            rowLabel(row.project, row.task, row.client)
                            ForEach(0..<7, id: \.self) { day in
                                HoursCell(
                                    entries: row.entriesByDay[day],
                                    hours: row.hoursByDay[day],
                                    target: TimerTarget(project: row.project, task: row.task, client: row.client),
                                    date: sheet.days[day],
                                    format: format
                                )
                            }
                            totalText(row.total, format: format)
                        }
                    }
                    ForEach(addedRows(excluding: sheet)) { target in
                        GridRow {
                            rowLabel(target.project, target.task, target.client)
                            ForEach(0..<7, id: \.self) { day in
                                HoursCell(entries: [], hours: 0, target: target, date: sheet.days[day], format: format)
                            }
                            totalText(0, format: format)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text("Total").font(.callout.weight(.semibold)).gridColumnAlignment(.leading)
                        ForEach(0..<7, id: \.self) { day in
                            totalText(sheet.dayTotals[day], format: format, bold: true)
                        }
                        totalText(sheet.total, format: format, bold: true)
                    }
                }
                .padding(16)
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
        let candidates = (tracker.frequentTargets + tracker.targets)
            .reduce(into: [TimerTarget]()) { list, target in
                if !list.contains(where: { $0.id == target.id }) { list.append(target) }
            }
            .filter { !existing.contains($0.id) }

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

    private func addedRows(excluding sheet: Timesheet) -> [TimerTarget] {
        let existing = Set(sheet.rows.map(\.id))
        return addedTargets.filter { !existing.contains($0.id) }
    }

    private func dayHeaders(_ sheet: Timesheet) -> some View {
        GridRow {
            Color.clear.frame(width: 1, height: 1).gridColumnAlignment(.leading)
            ForEach(sheet.days.indices, id: \.self) { index in
                let date = sheet.days[index]
                VStack(spacing: 0) {
                    Text(date.startOfDay(), format: .dateTime.weekday(.abbreviated))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(date.startOfDay(), format: .dateTime.day())
                        .font(.callout.weight(date == .today() ? .bold : .regular))
                        .foregroundStyle(date == .today() ? Color.accentColor : .primary)
                }
                .frame(width: 72)
            }
            Text("Total").font(.caption).foregroundStyle(.secondary).frame(width: 72)
        }
    }

    private func rowLabel(_ project: Reference, _ task: Reference, _ client: Reference?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(project.name).font(.callout).lineLimit(1)
            Text("\(client.map { "\($0.name) · " } ?? "")\(task.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
        .gridColumnAlignment(.leading)
    }

    private func totalText(_ hours: Double, format: HoursFormat, bold: Bool = false) -> some View {
        Text(hours == 0 ? "–" : hours.formattedHours(format))
            .font(.callout.weight(bold ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(hours == 0 ? .tertiary : .primary)
            .frame(width: 72, alignment: .trailing)
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

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var isEditable: Bool { entries.count <= 1 && entries.first?.isLocked != true && entries.first?.isRunning != true }
    private var shown: String { hours == 0 ? "" : hours.formattedHours(format) }

    var body: some View {
        Group {
            if isEditable {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            } else {
                Text(shown)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 7)
                    .help(entries.count > 1 ? "\(entries.count) entries. Edit them in the explorer." : "This entry can’t be changed here.")
            }
        }
        .frame(width: 72)
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
}
