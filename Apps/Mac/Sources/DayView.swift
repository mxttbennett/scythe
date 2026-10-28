import ScytheCore
import SwiftUI

/// The menu bar popover: the visible day, what is on the clock, and where the day's time went.
struct DayView: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.openSettingsWindow) private var openSettings
    @Environment(\.openDesktopWindow) private var openDesktop

    /// By id rather than index, because starting or stopping a timer reorders the entries under it.
    @State private var selection: TrackedEntry.ID?
    /// Which entry, if any, has its notes field open. Held here so the panel can hand
    /// the keyboard over to it entirely, and so only one row can be editing.
    @State private var editingNotes: TrackedEntry.ID?
    /// The duration field open on an entry, on the same terms as the notes.
    @State private var editingHours: TrackedEntry.ID?
    /// The entry whose play press is waiting on the today-or-then question, so the
    /// keyboard's ⏎ raises the same offer the mouse gets.
    @State private var confirmingResume: TrackedEntry.ID?
    /// The entry ⌫ or the context menu has asked to delete, held here for the same
    /// reason.
    @State private var confirmingDelete: TrackedEntry.ID?
    /// The open form replaces the list, so the list's arrow keys and ⏎ must stand down.
    @State private var isAddingEntry = false
    private var isEditingField: Bool { editingNotes != nil || editingHours != nil || isAddingEntry }
    @FocusState private var isPanelFocused: Bool

    private var format: HoursFormat { HoursFormat(company: tracker.company) }

    private var breakdown: [HoursBucket] {
        EntryAnalytics(tracker.entries, asOf: tracker.now).byProject()
    }

    /// Recomputed rather than stored, so a selection whose entry has gone, such as a
    /// deleted one, selects nothing.
    private var effectiveSelection: TrackedEntry.ID? {
        guard let selection, tracker.entries.contains(where: { $0.id == selection }) else { return nil }
        return selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * uiScale) {
            if isAddingEntry {
                AddEntryForm(
                    initialDate: tracker.day,
                    onSubmit: addEntry,
                    onCancel: { isAddingEntry = false }
                )
            } else if tracker.connection == .needsCredentials {
                ConnectPrompt()
            } else {
                header
                if case .offline(let reason) = tracker.connection {
                    FailureBanner(reason: reason)
                }
                // Anchored to what is on the clock rather than to the visible day:
                // a budget is not a property of a day, and the question it answers
                // is about the thing being worked on now.
                if let active = tracker.activity.entry {
                    BudgetBar(entry: active, format: format)
                }
                Divider()
                entryList
                if !breakdown.isEmpty {
                    Divider()
                    DayBreakdown(buckets: breakdown, format: format)
                }
            }
            if !isAddingEntry {
                Divider()
                footer
            }
        }
        .uiPadding(12)
        .uiFrame(width: 380)
        // The ring is suppressed because the selected row already draws itself, and
        // two highlights read as two selections.
        .focusable()
        .focusEffectDisabled()
        .focused($isPanelFocused)
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.return) { activate() }
        // Not `onKeyPress(.delete)`: that is U+0008, and the Mac's ⌫ sends U+007F,
        // so it never matches. This is the command both delete keys raise.
        .onDeleteCommand(perform: requestDelete)
        .onAppear { isPanelFocused = true }
        .opensLinearInDesktopApp()
    }

    /// Every key here defers to an open notes or duration field. Relying on the text
    /// field to swallow them would leave the arrows moving the selection out from
    /// under somebody in the middle of typing.
    private func move(by offset: Int) -> KeyPress.Result {
        guard !isEditingField,
              let next = Self.selection(after: effectiveSelection, moving: offset, in: tracker.entries.map(\.id))
        else { return .ignored }
        selection = next
        return .handled
    }

    /// A click also hands the keyboard to the panel, so the arrows and ⏎ act on the row just
    /// picked — unless a field is open, which still owns the keyboard.
    private func select(_ id: TrackedEntry.ID) {
        selection = id
        if !isEditingField { isPanelFocused = true }
    }

    /// No selection, or one that has gone, starts from before the first entry.
    static func selection(
        after current: TrackedEntry.ID?,
        moving offset: Int,
        in ids: [TrackedEntry.ID]
    ) -> TrackedEntry.ID? {
        guard !ids.isEmpty else { return nil }
        let index = current.flatMap { ids.firstIndex(of: $0) } ?? -1
        return ids[min(max(index + offset, 0), ids.count - 1)]
    }

    /// ⏎ does whatever the selected entry's button does: stop or resume it.
    private func activate() -> KeyPress.Result {
        // Locked, so the row's own button is disabled: the keyboard must not do
        // what the mouse is forbidden. `resume` already refuses, but `stop` does
        // not, so a locked entry left running was reachable this way alone.
        guard !isEditingField, let id = effectiveSelection,
              let entry = tracker.entries.first(where: { $0.id == id }), !entry.isLocked
        else { return .ignored }
        // The same fork the play button offers: resuming a past day's entry
        // would charge the old day, so it asks rather than assumes.
        if !entry.isRunning, entry.spentDate != .today() {
            confirmingResume = entry.id
        } else {
            Task { await tracker.toggle(entry) }
        }
        return .handled
    }

    /// ⌫ on an entry asks to delete it — the one thing otherwise only a right-click
    /// reached, which nothing on screen admits to.
    private func requestDelete() {
        guard !isEditingField, let id = effectiveSelection,
              let entry = tracker.entries.first(where: { $0.id == id }), !entry.isLocked
        else { return }
        confirmingDelete = entry.id
    }

    private var header: some View {
        HStack {
            Button {
                Task { await tracker.shiftDay(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous day")
            .contentShape(.rect)
            .keyboardShortcut(.leftArrow, modifiers: .command)

            VStack(spacing: 0) {
                Text(dayTitle)
                    .uiFont(.headline)
                if !tracker.isToday {
                    Button("Back to today") {
                        Task { await tracker.goToToday() }
                    }
                    .buttonStyle(.link)
                    .uiFont(.caption)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                Task { await tracker.shiftDay(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next day")
            .contentShape(.rect)
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Text(tracker.totalHours.formattedHours(format))
                .uiFont(.headline, monospacedDigit: true)
                .uiFrame(minWidth: 52, alignment: .trailing)

            Button {
                isAddingEntry = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .uiFont(.title3)
                    .uiFrame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .help("Add a time entry (⌘N)")
            .accessibilityLabel("Add a time entry")
            .contentShape(.rect)
            .keyboardShortcut("n")
        }
    }

    private func addEntry(_ draft: EntryDraft) async {
        await tracker.addEntry(against: draft.target, on: draft.date, hours: draft.action.hours, notes: draft.notes)
        isAddingEntry = false
    }

    @ViewBuilder
    private var entryList: some View {
        if tracker.entries.isEmpty {
            Text(tracker.isToday ? "Nothing tracked yet today." : "Nothing tracked on this day.")
                .uiFont(.callout)
                .foregroundStyle(GlassInk.secondary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .uiPadding(.vertical, 10)
        } else {
            // The arrow keys can move the selection past the bottom of a long day, so
            // the list has to follow it.
            ScrollViewReader { proxy in
                SizedScrollView(maxHeight: 260 * uiScale) {
                    LazyVStack(spacing: 2 * uiScale) {
                        ForEach(tracker.entries) { entry in
                            EntryRow(
                                entry: entry,
                                format: format,
                                isSelected: effectiveSelection == entry.id,
                                onSelect: { select(entry.id) },
                                // Opening either field closes the other, wherever it
                                // is: the keyboard defers to "the open field", which
                                // must therefore be singular.
                                isEditingNotes: Binding(
                                    get: { editingNotes == entry.id },
                                    set: {
                                        editingNotes = $0 ? entry.id : nil
                                        if $0 { editingHours = nil }
                                    }
                                ),
                                isEditingHours: Binding(
                                    get: { editingHours == entry.id },
                                    set: {
                                        editingHours = $0 ? entry.id : nil
                                        if $0 { editingNotes = nil }
                                    }
                                ),
                                isConfirmingResume: Binding(
                                    get: { confirmingResume == entry.id },
                                    set: { confirmingResume = $0 ? entry.id : nil }
                                ),
                                isConfirmingDelete: Binding(
                                    get: { confirmingDelete == entry.id },
                                    set: { confirmingDelete = $0 ? entry.id : nil }
                                )
                            )
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: effectiveSelection) {
                    guard let id = effectiveSelection else { return }
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8 * uiScale) {
            SyncStatusLabel()
            Spacer()
            Button(action: openDesktop) {
                Image(systemName: "macwindow")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Open the Scythe window")
            .accessibilityLabel("Open the Scythe window")
            .contentShape(.rect)
            .keyboardShortcut("1")

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
            .contentShape(.rect)
            .keyboardShortcut(",")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Quit Scythe")
            .accessibilityLabel("Quit Scythe")
            .contentShape(.rect)
            .keyboardShortcut("q")
        }
        .uiFont(.caption)
    }

    private var dayTitle: String {
        if tracker.isToday { return "Today" }
        return tracker.day.startOfDay().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// A sync failure the user can actually read. The status dot alone is too quiet
/// when the list is empty, because an empty day and a failed load look identical.
struct FailureBanner: View {
    @Environment(\.uiScale) private var uiScale
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * uiScale) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(reason)
                .uiFont(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .uiPadding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6 * uiScale))
    }
}

/// One line describing whether Harvest and Scythe agree yet.
struct SyncStatusLabel: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        HStack(spacing: 5 * uiScale) {
            Circle()
                .fill(color)
                .uiFrame(width: 6, height: 6)
            Text(message)
                .foregroundStyle(GlassInk.secondary(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(detail)
    }

    private var color: Color {
        switch tracker.connection {
        case .online: tracker.pendingCount > 0 ? .yellow : .green
        case .connecting: .yellow
        case .offline: .orange
        case .needsCredentials: .secondary
        }
    }

    private var message: String {
        switch tracker.connection {
        case .needsCredentials:
            return "Not connected"
        case .connecting:
            return "Connecting…"
        case .offline:
            return tracker.pendingCount > 0 ? "Offline · \(tracker.pendingCount.formatted()) queued" : "Offline"
        case .online:
            if tracker.pendingCount > 0 { return "Syncing \(tracker.pendingCount.formatted())…" }
            guard let synced = tracker.lastSyncedAt else { return "Synced" }
            // Reading `now` keeps this label live; the relative formatter renders a
            // just-finished sync as "in 0 seconds", which reads like the future.
            let elapsed = tracker.now.timeIntervalSince(synced)
            guard elapsed >= 45 else { return "Synced just now" }
            return "Synced \(synced.formatted(.relative(presentation: .numeric)))"
        }
    }

    private var detail: String {
        if case .offline(let reason) = tracker.connection { return reason }
        return "Scythe keeps working offline and sends changes when Harvest is reachable."
    }
}

/// Shown before any credentials exist, so the popover is never just empty.
struct ConnectPrompt: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettingsWindow) private var openSettings

    var body: some View {
        VStack(spacing: 8 * uiScale) {
            Image(systemName: "clock.badge.questionmark")
                .uiFont(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Connect to Harvest")
                .uiFont(.headline)
            Text("Scythe needs a personal access token before it can track anything.")
                .uiFont(.caption)
                .foregroundStyle(GlassInk.secondary(for: colorScheme))
                .multilineTextAlignment(.center)
            Button("Open Settings…", action: openSettings)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .uiPadding(.vertical, 12)
    }
}
