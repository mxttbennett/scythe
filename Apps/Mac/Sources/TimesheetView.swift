import ScytheCore
import SwiftUI

/// One week as a grid, editable in place: a cell with a single entry changes its hours,
/// and an empty cell logs a new one.
struct TimesheetView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker

    @AppStorage("timesheetSelectedWeek") private var selectedWeek = ""
    @AppStorage("timesheetLayout") private var layout = "week"
    /// Rows the user added for a project and task that have nothing logged this week yet.
    @State private var addedTargets: [TimerTarget] = []
    @State private var isChoosingTarget = false
    @State private var isChoosingWeek = false
    @State private var weekPickerDate = Date()
    @State private var reviewDay = CalendarDate.today()

    private var currentWeekStart: CalendarDate {
        CalendarDate(iso: selectedWeek)
            ?? CalendarDate.today().startOfWeek(weekStart: history.weekStart)
    }

    var body: some View {
        let start = currentWeekStart
        let sheet = Timesheet.build(from: history.entries, weekStart: start)
        let format = history.hoursFormat

        VStack(spacing: 0) {
            header(start: start, sheet: sheet, format: format)
            Divider()
            if layout == "day" {
                dayReviewContent(week: sheet.days, format: format)
            } else {
                sheetContent(sheet: sheet, format: format)
            }
        }
        .toolbar { ToolbarItemGroup { RefreshButton() } }
        .onAppear { alignReviewDay(to: start) }
    }

    @ViewBuilder
    private func sheetContent(sheet: Timesheet, format: HoursFormat) -> some View {
        let extraRows = addedRows(excluding: sheet)

        if history.entries.isEmpty, history.isRefreshing, extraRows.isEmpty {
            ProgressView("Loading your history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if history.entries.isEmpty, extraRows.isEmpty {
            HistoryUnavailableView(systemImage: "calendar")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sheet.rows.isEmpty, extraRows.isEmpty {
            ContentUnavailableView {
                Label("No entries this week", systemImage: "calendar")
            } description: {
                Text("Use Add Row to log hours against a project for this week.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                let totalWidth: CGFloat = 64
                let spacing: CGFloat = 6
                let gridWidth = max(0, geometry.size.width - 32 - spacing * 8)
                let preferredLabelWidth = min(560, max(128, gridWidth * 0.4))
                let dayWidth = min(170, max(48, (gridWidth - preferredLabelWidth - totalWidth) / 7))
                let labelWidth = min(560, max(128, gridWidth - 7 * dayWidth - totalWidth))

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
                        ForEach(extraRows) { target in
                            GridRow {
                                rowLabel(target.project, target.task, target.client, width: labelWidth)
                                ForEach(0..<7, id: \.self) { day in
                                    HoursCell(
                                        entries: [],
                                        hours: 0,
                                        target: target,
                                        date: sheet.days[day],
                                        format: format,
                                        width: dayWidth
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
    }

    // MARK: - Pieces

    private func header(start: CalendarDate, sheet: Timesheet, format: HoursFormat) -> some View {
        let weekTitle = "\(start.startOfDay().formatted(.dateTime.month(.abbreviated).day())) – \(sheet.days[6].startOfDay().formatted(.dateTime.month(.abbreviated).day().year()))"

        return HStack(spacing: 10) {
            Button { selectWeek(start.adding(days: -7)) } label: { Image(systemName: "chevron.left") }
                .help("Previous week (⌘←)")
                .accessibilityLabel("Previous week")
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button { selectWeek(start.adding(days: 7)) } label: { Image(systemName: "chevron.right") }
                .help("Next week (⌘→)")
                .accessibilityLabel("Next week")
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Text(weekTitle)
                .font(.headline)
            Button {
                weekPickerDate = start.startOfDay()
                isChoosingWeek = true
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .help("Choose a week")
            .accessibilityLabel("Choose a week")
            .accessibilityValue(weekTitle)
            .popover(isPresented: $isChoosingWeek, arrowEdge: .bottom) {
                weekPicker
            }
            Button("This Week") { selectWeek(nil) }
                .disabled(CalendarDate(iso: selectedWeek) == nil)
            Picker("Timesheet view", selection: $layout) {
                Text("Week").tag("week")
                Text("Day Review").tag("day")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
            Spacer()
            addMenu(sheet: sheet)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var weekPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Week containing", selection: $weekPickerDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
            HStack {
                Button("Cancel") { isChoosingWeek = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Go to Week", action: showPickedWeek)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func showPickedWeek() {
        let selectedWeek = CalendarDate(weekPickerDate).startOfWeek(weekStart: history.weekStart)
        let currentWeek = CalendarDate.today().startOfWeek(weekStart: history.weekStart)
        selectWeek(selectedWeek == currentWeek ? nil : selectedWeek)
        isChoosingWeek = false
    }

    private func selectWeek(_ week: CalendarDate?) {
        let offset = min(6, max(0, reviewDay.daysSince(currentWeekStart)))
        let destination = week ?? CalendarDate.today().startOfWeek(weekStart: history.weekStart)
        selectedWeek = week?.description ?? ""
        reviewDay = destination.adding(days: offset)
    }

    private func alignReviewDay(to weekStart: CalendarDate) {
        let today = CalendarDate.today()
        let todayWeek = today.startOfWeek(weekStart: history.weekStart)
        reviewDay = weekStart.adding(days: today.daysSince(todayWeek))
    }

    private func dayReviewContent(week: [CalendarDate], format: HoursFormat) -> some View {
        let days = Set(week)
        var entriesByID = Dictionary(
            uniqueKeysWithValues: history.entries.filter { days.contains($0.spentDate) }.map { ($0.id, $0) }
        )
        for entry in tracker.entries where days.contains(entry.spentDate) {
            entriesByID[entry.id] = entry
        }
        return TimesheetDayReviewView(
            week: week,
            selectedDay: $reviewDay,
            entries: Array(entriesByID.values),
            isRefreshing: history.entries.isEmpty && history.isRefreshing,
            format: format
        )
    }

    private func addMenu(sheet: Timesheet) -> some View {
        let existing = Set(sheet.rows.map(\.id) + addedTargets.map(\.id))
        let candidates = Self.orderedUniqueTargets(tracker.frequentTargets + tracker.targets, excluding: existing)

        return SearchableChoiceMenu(
            title: "Add Row",
            current: "Add Row",
            items: candidates,
            selectedID: nil,
            searchPrompt: "Search projects and tasks",
            emptyMessage: "No project or task matches your search.",
            isPresented: $isChoosingTarget,
            label: { "\($0.projectLabel) — \($0.task.name)" },
            searchText: { target in
                [target.client?.name, target.project.name, target.task.name]
                    .compactMap { $0 }
                    .joined(separator: " ")
            },
            choose: { addedTargets.append($0) },
            showsTitle: false,
            usesButtonBackground: false,
            fillsAvailableWidth: false,
            anchorSystemImage: "plus"
        )
        .fixedSize()
        .disabled(candidates.isEmpty)
        .help(
            candidates.isEmpty
                ? "All available project and task rows are already on this timesheet."
                : "Add a project and task as an empty row for this week."
        )
        .accessibilityHint(
            candidates.isEmpty
                ? "All available project and task rows are already on this timesheet."
                : "Adds a project and task as an empty row for this week."
        )
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(date.startOfDay().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .frame(width: dayWidth)
            }
            Text("Total").font(.caption).foregroundStyle(GlassInk.secondary).frame(width: totalWidth)
        }
    }

    private func rowLabel(_ project: Reference, _ task: Reference, _ client: Reference?, width: CGFloat) -> some View {
        let detail = "\(client.map { "\($0.name) · " } ?? "")\(task.name)"
        return VStack(alignment: .leading, spacing: 1) {
            Text(project.name).font(.callout).lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .gridColumnAlignment(.leading)
        .help("\(project.name)\n\(detail)")
    }

    private func totalText(_ hours: Double, format: HoursFormat, bold: Bool = false, width: CGFloat) -> some View {
        Text(hours == 0 ? "–" : hours.formattedHours(format))
            .font(.callout.weight(bold ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(hours == 0 ? GlassInk.tertiary : AnyShapeStyle(.primary))
            .accessibilityLabel(hours == 0 ? "No hours" : hours.formattedHours(format))
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
    private var accessibilityLabel: String {
        "\(target.projectLabel), \(target.task.name), \(date.startOfDay().formatted(.dateTime.weekday(.wide).month(.wide).day()))"
    }
    private var accessibilityHoursValue: String { hours == 0 ? "No hours" : hours.formattedHours(format) }
    private var entryHint: String { "Enter hours as 1.5 or hours and minutes as 1:30." }

    var body: some View {
        Group {
            if isEditable {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(accessibilityHoursValue)
                    .accessibilityHint(entryHint)
                    .help(entryHint)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            } else {
                Text(shown)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(isRunning ? AnyShapeStyle(Color.accentColor) : GlassInk.secondary)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(isRunning ? "Timer running, \(accessibilityHoursValue)" : accessibilityHoursValue)
                    .accessibilityHint(helpText)
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
