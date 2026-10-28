import AppKit
import ScytheCore
import SwiftUI
import UniformTypeIdentifiers

extension TrackedEntry {
    /// Sortable text for table columns, which need a non-optional `Comparable` key path.
    var clientName: String { client?.name ?? "" }
    var projectName: String { project.name }
    var taskName: String { task.name }
    var noteText: String { notes ?? "" }
}

struct ExplorerView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(DesktopState.self) private var state
    @Environment(EntryDateFormatPreference.self) private var dateFormat

    @State private var sortOrder = [KeyPathComparator(\TrackedEntry.spentDate, order: .reverse)]
    @State private var selection = Set<TrackedEntry.ID>()
    @State private var editing: TrackedEntry?
    @State private var deleting: TrackedEntry?
    @State private var rowCache = ExplorerRowCache()

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
                table(rows, format: format, dateFormat: dateFormat.format)
            }
            Divider()
            summary(rows, format: format)
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

                Button {
                    export(rows)
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(rows.isEmpty)
                .help("Export what is shown as CSV")

                RefreshButton()
            }
        }
        .sheet(item: $editing) { entry in
            EditEntrySheet(entry: entry, format: format)
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
    }

    private func selected(in rows: [TrackedEntry]) -> TrackedEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return rows.first { $0.id == id }
    }

    private func table(_ rows: [TrackedEntry], format: HoursFormat, dateFormat: EntryDateFormat) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.spentDate) { entry in
                Text(dateFormat.formatted(entry.spentDate))
            }
            .width(min: 110, ideal: 120)

            TableColumn("Client", value: \.clientName) { entry in
                if !entry.clientName.isEmpty {
                    DotLabel(name: entry.clientName, kind: .client)
                }
            }
            .width(min: 92, ideal: 122)

            TableColumn("Project", value: \.projectName) { entry in
                DotLabel(name: entry.projectName, kind: .project)
            }
            .width(min: 112, ideal: 152)

            TableColumn("Task", value: \.taskName) { entry in
                DotLabel(name: entry.taskName, kind: .task)
            }
            .width(min: 102, ideal: 132)

            TableColumn("Notes", value: \.noteText) { entry in
                Text(NoteLinks.attributed(entry.noteText))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .width(min: 220)

            TableColumn("Link") { entry in
                if let url = entry.permalink {
                    EntryLink(url: url)
                }
            }
            .width(44)

            TableColumn("Hours", value: \.bankedHours) { entry in
                HStack(spacing: 4) {
                    if entry.isLocked {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(entry.bankedHours.formattedHours(format)).monospacedDigit()
                }
            }
            .width(min: 70, ideal: 80)
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

    private func summary(_ rows: [TrackedEntry], format: HoursFormat) -> some View {
        let analytics = EntryAnalytics(rows)
        return HStack(spacing: 16) {
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

    private func export(_ rows: [TrackedEntry]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "scythe-entries-\(CalendarDate.today()).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVExport.entries(rows).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
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
        .disabled(history.isRefreshing)
        .help("Refresh from Harvest")
        .keyboardShortcut("r")
    }
}

/// Project, task, notes and duration for one entry, with the same rules as the menu bar
/// panel: an untouched duration sends nothing, and a locked entry cannot be changed.
struct EditEntrySheet: View {
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss

    let entry: TrackedEntry
    @State private var notes: String
    @State private var hours: String
    @State private var projectID: Int
    @State private var taskID: Int
    private let hoursAsOpened: String

    init(entry: TrackedEntry, format: HoursFormat) {
        self.entry = entry
        let formatted = entry.bankedHours.formattedHours(format)
        _notes = State(initialValue: entry.notes ?? "")
        _hours = State(initialValue: formatted)
        _projectID = State(initialValue: entry.project.id)
        _taskID = State(initialValue: entry.task.id)
        hoursAsOpened = formatted
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
                    .foregroundStyle(.secondary)
                Text(entry.spentDate.startOfDay(), format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Project", selection: $projectID) {
                    ForEach(projects) { choice in
                        Text(label(choice.client, choice.project)).tag(choice.id)
                    }
                }
                Picker("Task", selection: $taskID) {
                    ForEach(taskChoices) { task in
                        Text(task.name).tag(task.id)
                    }
                }
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
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(entry.isLocked)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newHours = HoursEdit.commit(
            draft: hours, asOpened: hoursAsOpened, banked: entry.bankedHours, isRunning: entry.isRunning
        )
        let notesChanged = trimmed != (entry.notes ?? "")
        let targetChanged = projectID != entry.project.id || taskID != entry.task.id
        let newTarget = projects.first { $0.id == projectID }.flatMap { project in
            taskChoices.first { $0.id == taskID }.map { project.target(task: $0) }
        }
        let entry = entry
        Task {
            if notesChanged { await history.updateNotes(entry, to: trimmed) }
            if let newHours { await history.updateHours(entry, to: newHours) }
            if targetChanged, let newTarget { await history.updateTarget(entry, to: newTarget) }
        }
        dismiss()
    }
}
