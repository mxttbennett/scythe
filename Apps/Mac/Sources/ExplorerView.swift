import ScytheCore
import SwiftUI

extension TrackedEntry {
    /// Sortable text for table columns, which need a non-optional `Comparable` key path.
    var clientName: String { client?.name ?? "" }
    var projectName: String { project.name }
    var taskName: String { task.name }
    var noteText: String { notes ?? "" }
}

struct ExplorerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker
    @Environment(DesktopState.self) private var state
    @Environment(EntryDateFormatPreference.self) private var dateFormat

    @State private var sortOrder = [KeyPathComparator(\TrackedEntry.spentDate, order: .reverse)]
    @State private var selection = Set<TrackedEntry.ID>()
    @State private var editing: TrackedEntry?
    @State private var deleting: TrackedEntry?
    @State private var rowCache = ExplorerRowCache()
    @AppStorage("explorerWrapNotes") private var wrapNotes = true
    @AppStorage("explorerTableCustomization") private var columnCustomizationData = Data()

    // The Explorer uses an AppKit-managed window, so keep this Codable state at app scope.
    private var columnCustomization: Binding<TableColumnCustomization<TrackedEntry>> {
        Binding(
            get: {
                (try? JSONDecoder().decode(TableColumnCustomization<TrackedEntry>.self, from: columnCustomizationData))
                    ?? TableColumnCustomization()
            },
            set: { columnCustomizationData = (try? JSONEncoder().encode($0)) ?? Data() }
        )
    }

    var body: some View {
        let rows = rowCache.rows(
            entries: history.entries, version: history.entriesVersion, index: history.searchIndex,
            filter: state.filter, weekStart: history.weekStart, today: .today(), order: sortOrder
        )
        let format = history.hoursFormat

        VStack(spacing: 0) {
            if rows.isEmpty {
                emptyState
            } else {
                // The rows measure their own height once and keep it, so a change to every row's height needs a fresh table.
                table(rows, format: format, dateFormat: dateFormat.format)
                    .id(wrapNotes)
            }
            Divider()
            ExplorerSummary(rows: rows, format: format)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editing = selected(in: rows)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(selected(in: rows).map(\.isLocked) ?? true)
                .help("Edit the selected entry")

                Button {
                    deleting = selected(in: rows)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selected(in: rows).map(\.isLocked) ?? true)
                .help("Delete the selected entry")

                CSVExportButton(rows: rows)

                Toggle(isOn: $wrapNotes) {
                    Label("Wrap notes", systemImage: "text.alignleft")
                }
                .toggleStyle(.button)
                .help(wrapNotes ? "Show each note on one line" : "Wrap long notes in full")

                RefreshButton()
            }
        }
        .overlay {
            if let entry = editing {
                DismissibleModalOverlay(onDismiss: { editing = nil }) {
                    EditEntrySheet(entry: entry, format: format, asOf: tracker.now) { editing = nil }
                }
            }
        }
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { entry in
            Button("Delete", role: .destructive) {
                Task { await history.delete(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("\(entry.bankedHours.formattedHours(format)) on \(entry.task.name) will be removed from Harvest. This cannot be undone.")
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: editing != nil)
    }

    private func selected(in rows: [TrackedEntry]) -> TrackedEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return rows.first { $0.id == id }
    }

    private func table(_ rows: [TrackedEntry], format: HoursFormat, dateFormat: EntryDateFormat) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: columnCustomization) {
            TableColumn("Date", value: \.spentDate) { entry in
                Text(dateFormat.formatted(entry.spentDate))
                    .help(dateFormat.formatted(entry.spentDate))
            }
            .width(min: 130, ideal: 130, max: 170)
            .customizationID("date")

            TableColumn("Client", value: \.clientName) { entry in
                if !entry.clientName.isEmpty {
                    DotLabel(name: entry.clientName, kind: .client)
                        .help(entry.clientName)
                }
            }
            .width(min: 58, ideal: 64, max: 110)
            .customizationID("client")

            TableColumn("Project", value: \.projectName) { entry in
                DotLabel(name: entry.projectName, kind: .project)
                    .help(entry.projectName)
            }
            .width(min: 70, ideal: 80, max: 130)
            .customizationID("project")

            TableColumn("Task", value: \.taskName) { entry in
                DotLabel(name: entry.taskName, kind: .task, maxLines: 2)
                    .help(entry.taskName)
            }
            .width(min: 220, ideal: 280, max: 380)
            .customizationID("task")

            TableColumn("Notes", value: \.noteText) { entry in
                NotesCell(text: entry.noteText, wraps: wrapNotes)
                    .help(entry.noteText)
            }
            .width(min: 105, ideal: 120, max: 220)
            .customizationID("notes")

            TableColumn("Link") { entry in
                if let url = entry.permalink {
                    EntryLink(url: url)
                }
            }
            .width(32)
            .customizationID("link")

            TableColumn("Hours", value: \.bankedHours) { entry in
                HStack(spacing: 4) {
                    if entry.isLocked {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(GlassInk.secondary)
                    }
                    LiveHours(tracker: tracker, entry: entry, format: format)
                }
            }
            .width(min: 64, ideal: 68, max: 90)
            .customizationID("hours")
        }
        .background(DateColumnMenu(preference: self.dateFormat))
        .contextMenu(forSelectionType: TrackedEntry.ID.self) { ids in
            if ids.count == 1, let entry = rows.first(where: { $0.id == ids.first }), !entry.isLocked {
                Button("Edit…") { editing = entry }
                Button("Delete…", role: .destructive) { deleting = entry }
            }
        } primaryAction: { ids in
            if ids.count == 1, let entry = rows.first(where: { $0.id == ids.first }), !entry.isLocked {
                editing = entry
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if history.entries.isEmpty {
            if history.isRefreshing {
                ProgressView("Loading your history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "tray",
                    description: Text(history.failure ?? "Entries from Harvest appear here once connected.")
                )
            }
        } else {
            ContentUnavailableView {
                Label("No matching entries", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing in your history fits this filter.")
            } actions: {
                Button("Clear Filter") { state.filter = EntryFilter() }
            }
        }
    }
}

struct DismissibleModalOverlay<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(1)
        .transition(.opacity)
    }
}

struct RefreshButton: View {
    @Environment(HistoryModel.self) private var history

    var body: some View {
        Button {
            Task { await history.refresh() }
        } label: {
            if history.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .accessibilityLabel(history.isRefreshing ? "Refreshing history" : "Refresh from Harvest")
        .disabled(history.isRefreshing)
        .help("Refresh from Harvest (⌘R)")
        .keyboardShortcut("r")
    }
}

/// Project, task, notes and duration for one entry, with the same rules as the menu bar
/// panel: an untouched duration sends nothing, and a locked entry cannot be changed.
struct EditEntrySheet: View {
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker

    let entry: TrackedEntry
    let onDismiss: () -> Void
    @State private var notes: String
    @State private var hours: String
    @State private var spentDate: CalendarDate
    @State private var projectID: Int
    @State private var taskID: Int
    @State private var hoursAsOpened: String
    @State private var isConfirmingDelete = false
    @State private var isChoosingProject = false
    @State private var isChoosingTask = false

    init(entry: TrackedEntry, format: HoursFormat, asOf: Date = Date(), onDismiss: @escaping () -> Void = {}) {
        self.entry = entry
        self.onDismiss = onDismiss
        let formatted = entry.hours(asOf: asOf).formattedHours(format)
        _notes = State(initialValue: entry.notes ?? "")
        _hours = State(initialValue: formatted)
        _hoursAsOpened = State(initialValue: formatted)
        _spentDate = State(initialValue: entry.spentDate)
        _projectID = State(initialValue: entry.project.id)
        _taskID = State(initialValue: entry.task.id)
    }

    /// The entry's own project stays on offer after it is unassigned, so opening the sheet never loses it.
    private var projects: [ProjectTargets] {
        let assigned = tracker.orderedProjects
        guard !assigned.contains(where: { $0.id == entry.project.id }) else { return assigned }
        return [ProjectTargets(project: entry.project, client: entry.client, tasks: [entry.task])] + assigned
    }

    private var taskChoices: [Reference] {
        let tasks = projects.first { $0.id == projectID }?.tasks ?? []
        guard projectID == entry.project.id, !tasks.contains(where: { $0.id == entry.task.id }) else { return tasks }
        return [entry.task] + tasks
    }

    private func label(_ client: Reference?, _ project: Reference) -> String {
        "\(client.map { "\($0.name) · " } ?? "")\(project.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.task.name).font(.headline)
                Text(label(entry.client, entry.project))
                    .foregroundStyle(GlassInk.secondary)
                Text(spentDate.startOfDay(), format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.callout)
                    .foregroundStyle(GlassInk.secondary)
            }

            Form {
                LabeledContent("Project") {
                    SearchableChoiceMenu(
                        title: "Project",
                        current: projects.first { $0.id == projectID }.map { label($0.client, $0.project) } ?? "",
                        items: projects,
                        selectedID: projectID,
                        searchPrompt: "Search projects",
                        emptyMessage: "No projects match your search.",
                        isPresented: $isChoosingProject,
                        label: { label($0.client, $0.project) },
                        searchText: { label($0.client, $0.project) },
                        choose: { projectID = $0.id },
                        showsTitle: false
                    )
                }
                LabeledContent("Task") {
                    SearchableChoiceMenu(
                        title: "Task",
                        current: taskChoices.first { $0.id == taskID }?.name ?? "",
                        items: taskChoices,
                        selectedID: taskID,
                        searchPrompt: "Search tasks",
                        emptyMessage: "No tasks match your search.",
                        isPresented: $isChoosingTask,
                        label: \.name,
                        searchText: \.name,
                        choose: { taskID = $0.id },
                        showsTitle: false
                    )
                }
                DatePicker("Date", selection: Binding(
                    get: { spentDate.startOfDay() },
                    set: { spentDate = CalendarDate($0) }
                ), displayedComponents: .date)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Hours", text: $hours)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
            }
            .formStyle(.columns)
            .disabled(entry.isLocked)
            .onChange(of: projectID) {
                let project = projects.first { $0.id == projectID }
                taskID = project?.task(chosenFrom: [projectID: taskID])?.id ?? taskID
            }

            if entry.isLocked {
                Label("Approved or invoiced. Harvest won’t accept changes.", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(GlassInk.secondary)
            }

            HStack {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(entry.isLocked)

                Spacer()
                Button("Cancel", role: .cancel, action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Save (⌘↩)", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(entry.isLocked)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: tracker.entries) {
            Task {
                guard let current = await tracker.currentEntry(matching: entry.id) else { return }
                if notes == (entry.notes ?? "") {
                    notes = current.notes ?? ""
                }
                if hours == hoursAsOpened {
                    let currentHours = current.hours(asOf: tracker.now).formattedHours(history.hoursFormat)
                    hours = currentHours
                    hoursAsOpened = currentHours
                }
                if spentDate == entry.spentDate { spentDate = current.spentDate }
            }
        }
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if let current = await tracker.currentEntry(matching: entry.id) {
                        await history.delete(current)
                    }
                    onDismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(entry.hours(asOf: tracker.now).formattedHours(history.hoursFormat)) on \(entry.task.name) will be removed from Harvest. This cannot be undone.")
        }
    }

    private func save() {
        Task {
            guard let current = await tracker.currentEntry(matching: entry.id) else { return }
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let newHours = HoursEdit.commit(
                draft: hours,
                asOpened: hoursAsOpened,
                banked: current.bankedHours,
                isRunning: current.isRunning
            )
            let notesChanged = trimmed != (current.notes ?? "")
            let targetChanged = projectID != current.project.id || taskID != current.task.id
            let newTarget = targetChanged ? projects.first { $0.id == projectID }.flatMap { project in
                taskChoices.first { $0.id == taskID }.map { project.target(task: $0) }
            } : nil
            await history.updateEntry(
                current,
                notes: notesChanged ? trimmed : nil,
                hours: newHours,
                target: newTarget,
                spentDate: spentDate == current.spentDate ? nil : spentDate
            )
        }
        onDismiss()
    }
}
