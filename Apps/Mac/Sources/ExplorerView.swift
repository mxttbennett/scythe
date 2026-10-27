import AppKit
import SheavesCore
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

    @State private var sortOrder = [KeyPathComparator(\TrackedEntry.spentDate, order: .reverse)]
    @State private var selection = Set<TrackedEntry.ID>()
    @State private var editing: TrackedEntry?
    @State private var deleting: TrackedEntry?

    var body: some View {
        let rows = state.filter.apply(to: history.entries, weekStart: history.weekStart).sorted(using: sortOrder)
        let format = history.hoursFormat

        VStack(spacing: 0) {
            if rows.isEmpty {
                emptyState
            } else {
                table(rows, format: format)
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

    private func table(_ rows: [TrackedEntry], format: HoursFormat) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.spentDate) { entry in
                Text(entry.spentDate.startOfDay(), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            }
            .width(min: 110, ideal: 120)

            TableColumn("Client", value: \.clientName) { entry in
                Text(entry.clientName)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Project", value: \.projectName)
                .width(min: 100, ideal: 140)

            TableColumn("Task", value: \.taskName)
                .width(min: 90, ideal: 120)

            TableColumn("Notes", value: \.noteText) { entry in
                Text(NoteLinks.attributed(entry.noteText))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .width(min: 220)

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
        panel.nameFieldStringValue = "sheaves-entries-\(CalendarDate.today()).csv"
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

/// Notes and duration for one entry, with the same rules as the menu bar panel: an
/// untouched duration sends nothing, and a locked entry cannot be changed.
struct EditEntrySheet: View {
    @Environment(HistoryModel.self) private var history
    @Environment(\.dismiss) private var dismiss

    let entry: TrackedEntry
    @State private var notes: String
    @State private var hours: String
    private let hoursAsOpened: String

    init(entry: TrackedEntry, format: HoursFormat) {
        self.entry = entry
        let formatted = entry.bankedHours.formattedHours(format)
        _notes = State(initialValue: entry.notes ?? "")
        _hours = State(initialValue: formatted)
        hoursAsOpened = formatted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.task.name).font(.headline)
                Text("\(entry.client.map { "\($0.name) · " } ?? "")\(entry.project.name)")
                    .foregroundStyle(.secondary)
                Text(entry.spentDate.startOfDay(), format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Hours", text: $hours)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
            }
            .formStyle(.columns)
            .disabled(entry.isLocked)

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
        let entry = entry
        Task {
            if notesChanged { await history.updateNotes(entry, to: trimmed) }
            if let newHours { await history.updateHours(entry, to: newHours) }
        }
        dismiss()
    }
}
