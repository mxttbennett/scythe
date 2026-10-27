import SheavesCore
import SwiftUI

struct EntryRow: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.colorScheme) private var colorScheme

    let entry: TrackedEntry
    var format: HoursFormat
    var isSelected: Bool = false
    /// Held by the panel rather than the row, so that only one row can be editing at
    /// a time and so the panel knows to leave the keyboard alone while one is.
    @Binding var isEditingNotes: Bool
    /// Same arrangement for the duration, which is a field the way the notes are.
    @Binding var isEditingHours: Bool
    /// Play on a past day's entry asks first — resuming it would charge the old
    /// day. The panel holds this too, so the keyboard's ⏎ can raise the same offer.
    @Binding var isConfirmingResume: Bool
    /// Held by the panel for the same reason, so ⌫ raises the question the context
    /// menu does.
    @Binding var isConfirmingDelete: Bool
    @State private var draftNotes = ""
    @State private var draftHours = ""
    /// What the duration field was showing when it opened. A field still showing it
    /// has asked for nothing — see `HoursEdit.commit`, which is where that matters.
    @State private var hoursAsOpened = ""
    /// Set by Escape on its way out, because a field that has already gone cannot be
    /// asked why it went. Everything else that closes one — ⏎, a click on the field
    /// beside it, another row opening its own — keeps what was typed.
    @State private var isDiscardingNotes = false
    @State private var isDiscardingHours = false
    @FocusState private var isNotesFocused: Bool
    @FocusState private var isHoursFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.task.name)
                    .font(.callout)
                    .fontWeight(entry.isRunning ? .semibold : .regular)
                    .lineLimit(1)
                Text(entry.target.projectLabel)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                notes
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            duration
            editMenu
            toggleButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? selectedText : AnyShapeStyle(.primary))
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        // Without a shape, the context menu only opens over drawn text.
        .contentShape(.rect)
        .contextMenu { editActions.disabled(entry.isLocked) }
        // Without this the row reads as disconnected fragments: task, project,
        // notes, two status icons and a duration, with the icons explained only by
        // a mouse-only tooltip.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: entry.isRunning ? "Stop timer" : "Resume timer") {
            requestToggle()
        }
        .accessibilityAction(named: entry.notes?.isEmpty == false ? "Edit notes" : "Add notes") {
            beginEditingNotes()
        }
        .accessibilityAction(named: "Edit time") { beginEditingHours() }
        .accessibilityAction(named: "Delete", requestDelete)
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await tracker.delete(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(entry.hours(asOf: tracker.now).formattedHours(format)) on \(entry.task.name) will be removed from Harvest. This cannot be undone.")
        }
        // Play on a past entry usually means "do that work now", not "backfill an
        // old day" — so it asks, the way Harvest's own app does. Both choices are
        // spelled out because neither is a cancel: one starts a fresh timer today
        // with the same project, task and notes; the other genuinely reopens the
        // old day.
        .confirmationDialog(
            "This entry is from \(entryDayLabel).",
            isPresented: $isConfirmingResume,
            titleVisibility: .visible
        ) {
            Button("Start on Today") {
                // To today first, then start: the dedupe in `start` can only see
                // the visible day's list, and starting blind from here duplicated
                // an entry the user already had today. Going there also puts the
                // new timer where the eye can follow it — a timer started on today
                // from yesterday's view used to vanish the moment it stopped.
                Task {
                    await tracker.goToToday()
                    await tracker.start(entry.target, notes: entry.notes)
                }
            }
            Button("Resume on \(entryDayLabel)") {
                Task { await tracker.resume(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starting on Today leaves \(entryDayLabel)’s time as it is.")
        }
    }

    private var entryDayLabel: String {
        entry.spentDate.startOfDay().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// What play or ⏎ should do: toggle, unless resuming would quietly charge a
    /// past day — then raise the offer instead. Locked means locked on every path:
    /// the accessibility action routes here too, and it must not offer what the
    /// disabled button will not.
    private func requestToggle() {
        guard !entry.isLocked else { return }
        if !entry.isRunning, entry.spentDate != .today() {
            isConfirmingResume = true
        } else {
            Task { await tracker.toggle(entry) }
        }
    }

    /// Asks rather than deletes, on every path. Harvest has no undo for this.
    private func requestDelete() {
        guard !entry.isLocked else { return }
        isConfirmingDelete = true
    }

    private var selectedText: AnyShapeStyle {
        AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
    }

    private var secondaryText: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor).opacity(0.8))
            : AnyShapeStyle(.secondary)
    }

    /// Selection outranks the running tint: a running row still says so with its
    /// weight and its stop button, where a selected row has only this to say it.
    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color(nsColor: .selectedContentBackgroundColor)) }
        return entry.isRunning ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear)
    }

    /// Spoken as one sentence, including what the status icons mean.
    private var accessibilityLabel: String {
        var parts = [entry.task.name, entry.target.projectLabel]
        if let notes = entry.notes, !notes.isEmpty { parts.append(notes) }
        parts.append(spokenDuration)
        if entry.isRunning { parts.append("timer running") }
        if entry.isPending { parts.append("waiting to sync") }
        if entry.isLocked { parts.append("locked, approved or invoiced") }
        return parts.joined(separator: ", ")
    }

    /// "1:14" is read as "one fourteen"; say what it means.
    private var spokenDuration: String {
        let total = Int((entry.hours(asOf: tracker.now) * 60).rounded())
        let hours = total / 60
        let minutes = total % 60
        switch (hours, minutes) {
        case (0, let m): return "\(m.formatted()) minute\(m == 1 ? "" : "s")"
        case (let h, 0): return "\(h.formatted()) hour\(h == 1 ? "" : "s")"
        case (let h, let m): return "\(h.formatted()) hour\(h == 1 ? "" : "s") \(m.formatted()) minute\(m == 1 ? "" : "s")"
        }
    }

    @ViewBuilder
    private var notes: some View {
        if isEditingNotes {
            TextField("Notes", text: $draftNotes)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($isNotesFocused)
                .onSubmit { isEditingNotes = false }
                .onExitCommand {
                    isDiscardingNotes = true
                    isEditingNotes = false
                }
                .onAppear { isNotesFocused = true }
                .onDisappear(perform: finishEditingNotes)
        } else if let text = entry.notes, !text.isEmpty {
            Text(NoteLinks.attributed(text))
                .font(.caption)
                .foregroundStyle(secondaryText)
                .tint(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.accentColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private var duration: some View {
        HStack(spacing: 4) {
            if entry.isPending {
                // A local change Harvest has not acknowledged yet.
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Waiting to sync")
            }
            if entry.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Approved or invoiced — Harvest won’t accept changes")
            }
            if isEditingHours {
                TextField("0:00", text: $draftHours)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
                    .focused($isHoursFocused)
                    .onSubmit { isEditingHours = false }
                    .onExitCommand {
                        isDiscardingHours = true
                        isEditingHours = false
                    }
                    .onDisappear(perform: finishEditingHours)
                    .onAppear {
                        // Normally prefilled by `beginEditingHours`; also here, so a
                        // render that opens the field directly (the documentation
                        // images) shows what a user would see.
                        if draftHours.isEmpty {
                            draftHours = entry.hours(asOf: tracker.now).formattedHours(format)
                            hoursAsOpened = draftHours
                        }
                        isHoursFocused = true
                    }
            } else {
                Text(entry.hours(asOf: tracker.now).formattedHours(format))
                    .font(.callout.monospacedDigit())
                    .fontWeight(entry.isRunning ? .semibold : .regular)
            }
        }
    }

    @ViewBuilder
    private var editActions: some View {
        Button(entry.notes?.isEmpty == false ? "Edit Notes…" : "Add Notes…") { beginEditingNotes() }
        Button("Edit Time…") { beginEditingHours() }
        Button("Delete…", role: .destructive, action: requestDelete)
    }

    private var editMenu: some View {
        Menu {
            editActions
        } label: {
            Image(systemName: "pencil")
                .font(.caption)
                .frame(width: 22, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // A borderless menu ignores foregroundStyle; the dark scheme is what turns its glyph white on the selection.
        .environment(\.colorScheme, isSelected ? .dark : colorScheme)
        .fixedSize()
        .disabled(entry.isLocked)
        .help("Edit")
        .accessibilityLabel("Edit entry")
    }

    private var toggleButton: some View {
        Button {
            requestToggle()
        } label: {
            Image(systemName: entry.isRunning ? "stop.fill" : "play.fill")
                .font(.caption)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .disabled(entry.isLocked)
        .help(entry.isRunning ? "Stop timer" : "Resume timer")
        .accessibilityLabel(entry.isRunning ? "Stop timer" : "Resume timer")
        .contentShape(.rect)
    }

    private func beginEditingNotes() {
        guard !entry.isLocked else { return }
        draftNotes = entry.notes ?? ""
        isEditingNotes = true
    }

    private func beginEditingHours() {
        guard !entry.isLocked else { return }
        draftHours = entry.hours(asOf: tracker.now).formattedHours(format)
        hoursAsOpened = draftHours
        isEditingHours = true
    }

    /// The field is gone by the time this runs, so it has to stand for every way it
    /// could have gone: ⏎, Escape, a click on the notes beside it, or another row
    /// opening a field of its own. Only Escape discards — clicking away from a
    /// half-typed duration used to throw it away, which is the one outcome nobody
    /// asks for.
    private func finishEditingHours() {
        guard !isDiscardingHours else {
            isDiscardingHours = false
            return
        }
        guard let hours = HoursEdit.commit(
            draft: draftHours,
            asOpened: hoursAsOpened,
            banked: entry.bankedHours,
            isRunning: entry.isRunning
        ) else { return }
        Task { await tracker.updateHours(entry, to: hours) }
    }

    /// Same terms as the duration above: kept unless Escape said otherwise.
    private func finishEditingNotes() {
        guard !isDiscardingNotes else {
            isDiscardingNotes = false
            return
        }
        let trimmed = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (entry.notes ?? "") else { return }
        Task { await tracker.updateNotes(entry, to: trimmed) }
    }
}
