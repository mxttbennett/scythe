import AppKit
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
    @Environment(\.uiScale) private var uiScale
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker
    @Environment(DesktopState.self) private var state
    @Environment(EntryDateFormatPreference.self) private var dateFormat

    @State private var sortOrder = [KeyPathComparator(\TrackedEntry.spentDate, order: .reverse)]
    @State private var selection = Set<TrackedEntry.ID>()
    @State private var rows: [TrackedEntry] = []
    @State private var tableGeneration = 0
    @State private var isComputingRows = true
    @State private var editing: TrackedEntry?
    @State private var deleting: TrackedEntry?
    @State private var confirmingResume: TrackedEntry?
    @State private var rowCache = ExplorerRowCache()
    @AppStorage("explorerWrapNotes") private var wrapNotes = true
    @AppStorage("explorerTableCustomizationV2") private var columnCustomizationData = Data()

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
        let request = ExplorerRowsRequest(
            version: history.entriesVersion, filter: state.filter, weekStart: history.weekStart,
            today: .today(), order: sortOrder
        )
        let format = history.hoursFormat

        VStack(spacing: 0) {
            if rows.isEmpty && isComputingRows {
                ProgressView("Updating entries…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                emptyState
            } else {
                // The rows measure their own height once and keep it, so a change to every row's height needs a fresh table.
                table(rows, format: format, dateFormat: dateFormat.format)
                    // Replacing the table avoids SwiftUI's expensive row-by-row diff when a
                    // filter removes thousands of entries. Keep the customization outside it.
                    .id("\(tableGeneration)-\(wrapNotes)")
            }
            Divider()
            ExplorerSummary(rows: rows, format: format)
        }
        .task(id: request) {
            isComputingRows = true
            let snapshot = await rowCache.rows(entries: history.entries, index: history.searchIndex, request: request)
            guard !Task.isCancelled else { return }
            rows = snapshot.entries
            tableGeneration = snapshot.generation
            isComputingRows = false
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editing = selected(in: rows)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(selected(in: rows).map(\.isLocked) ?? true)
                .help("Edit the selected entry (E or Return)")

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
                .help(wrapNotes ? "Show each note on one line" : "Wrap each note in up to three lines")

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
        .confirmationDialog(
            "This entry is from a past day.",
            isPresented: Binding(get: { confirmingResume != nil }, set: { if !$0 { confirmingResume = nil } }),
            titleVisibility: .visible,
            presenting: confirmingResume
        ) { entry in
            let day = entry.spentDate.startOfDay().formatted(.dateTime.weekday(.wide).month(.wide).day())
            Button("Start on Today") {
                Task {
                    await tracker.goToToday()
                    await tracker.start(entry.target, notes: entry.notes)
                }
            }
            Button("Resume on \(day)") {
                Task { await tracker.resume(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            let day = entry.spentDate.startOfDay().formatted(.dateTime.weekday(.wide).month(.wide).day())
            Text("Starting on Today leaves \(day)’s time as it is.")
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: editing != nil)
    }

    private func selected(in rows: [TrackedEntry]) -> TrackedEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return rows.first { $0.id == id }
    }

    private func editSelected(in rows: [TrackedEntry]) -> KeyPress.Result {
        guard let entry = selected(in: rows), !entry.isLocked else { return .ignored }
        editing = entry
        return .handled
    }

    private func toggleSelected(in rows: [TrackedEntry]) -> KeyPress.Result {
        guard let selected = selected(in: rows) else { return .ignored }
        let entry = tracker.entries.first(where: { $0.id == selected.id }) ?? selected
        guard !entry.isLocked else { return .ignored }
        requestToggle(entry)
        return .handled
    }

    private func requestToggle(_ rowEntry: TrackedEntry) {
        let entry = tracker.entries.first(where: { $0.id == rowEntry.id }) ?? rowEntry
        guard !entry.isLocked else { return }
        if !entry.isRunning, entry.spentDate != .today() {
            confirmingResume = entry
        } else {
            Task { await tracker.toggle(entry) }
        }
    }

    private func table(_ rows: [TrackedEntry], format: HoursFormat, dateFormat: EntryDateFormat) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: columnCustomization) {
            TableColumn("Date", value: \.spentDate) { entry in
                tableCell {
                    Text(dateFormat.formatted(entry.spentDate))
                        .help(dateFormat.formatted(entry.spentDate))
                }
            }
            .width(min: 130, ideal: 130, max: .infinity)
            .customizationID("date")

            TableColumn("Client", value: \.clientName) { entry in
                if !entry.clientName.isEmpty {
                    tableCell {
                        DotLabel(name: entry.clientName, kind: .client)
                            .help(entry.clientName)
                    }
                }
            }
            .width(min: 58, ideal: 64, max: .infinity)
            .customizationID("client")

            TableColumn("Project", value: \.projectName) { entry in
                tableCell {
                    DotLabel(name: entry.projectName, kind: .project)
                        .help(entry.projectName)
                }
            }
            .width(min: 70, ideal: 80, max: .infinity)
            .customizationID("project")

            TableColumn("Task", value: \.taskName) { entry in
                tableCell {
                    DotLabel(name: entry.taskName, kind: .task, maxLines: 2)
                        .help(entry.taskName)
                }
            }
            .width(min: 220, ideal: 280, max: .infinity)
            .customizationID("task")

            TableColumn("Link") { entry in
                tableCell(alignment: .center) {
                    if let url = entry.permalink {
                        EntryLink(url: url)
                    }
                }
            }
            .width(min: 32, ideal: 36, max: 72)
            .customizationID("link")

            TableColumn("Hours", value: \.bankedHours) { entry in
                tableCell {
                    HStack(spacing: 4) {
                        if entry.isLocked {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(GlassInk.secondary)
                        }
                        LiveHours(tracker: tracker, entry: entry, format: format)
                    }
                }
            }
            .width(min: 64, ideal: 68, max: 140)
            .customizationID("hours")

            TableColumn("Notes", value: \.noteText) { entry in
                tableCell {
                    NotesCell(text: entry.noteText, wraps: wrapNotes)
                        .help(entry.noteText)
                }
            }
            .width(min: 105, ideal: 120, max: .infinity)
            .customizationID("notes")
        }
        .background(DateColumnMenu(preference: self.dateFormat))
        .contextMenu(forSelectionType: TrackedEntry.ID.self) { ids in
            if ids.count == 1, let entry = rows.first(where: { $0.id == ids.first }), !entry.isLocked {
                let current = tracker.entries.first(where: { $0.id == entry.id }) ?? entry
                Button("Edit…") { editing = entry }
                    .keyboardShortcut("e")
                Button(current.isRunning ? "Stop Timer" : "Start Timer") {
                    requestToggle(entry)
                }
                .keyboardShortcut(current.isRunning ? .space : "s")
                Button("Delete…", role: .destructive) { deleting = entry }
            }
        } primaryAction: { ids in
            if ids.count == 1, let entry = rows.first(where: { $0.id == ids.first }), !entry.isLocked {
                editing = entry
            }
        }
        .onKeyPress(keys: ["e"], phases: .down) { _ in editSelected(in: rows) }
        .onKeyPress(.return, phases: .down) { _ in editSelected(in: rows) }
        .onKeyPress(keys: ["s"], phases: .down) { _ in toggleSelected(in: rows) }
        .onKeyPress(.space, phases: .down) { _ in toggleSelected(in: rows) }
    }

    private func tableCell<Content: View>(
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 36 * uiScale, alignment: alignment)
    }

    @ViewBuilder
    private var emptyState: some View {
        if history.entries.isEmpty {
            if history.isRefreshing {
                ProgressView("Loading your history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HistoryUnavailableView(systemImage: "tray")
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
            // Keep the editor distinct without washing the app's colors out behind it.
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content
                .background(
                    Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
