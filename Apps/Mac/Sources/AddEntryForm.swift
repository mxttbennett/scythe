import ScytheCore
import SwiftUI

/// Takes the submit action as a closure, so the panel and the window each store a draft their own way.
struct AddEntryForm: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.uiScale) private var uiScale

    let onSubmit: (EntryDraft) async -> Void
    let onCancel: () -> Void

    @State private var projectID: Int?
    @State private var taskID: Int?
    @State private var date: Date
    @State private var hoursText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @FocusState private var isHoursFocused: Bool

    init(
        initialDate: CalendarDate,
        onSubmit: @escaping (EntryDraft) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        _date = State(initialValue: initialDate.startOfDay())
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    private var projects: [ProjectTargets] { tracker.orderedProjects }
    private var selectedProject: ProjectTargets? { projects.first { $0.id == projectID } ?? projects.first }
    private var selectedTask: Reference? {
        selectedProject?.tasks.first { $0.id == taskID } ?? selectedProject?.tasks.first
    }
    private var chosenDate: CalendarDate { CalendarDate(date) }
    private var action: EntryAction? { EntryDraft.action(hoursText: hoursText, date: chosenDate) }
    private var canSubmit: Bool { action != nil && selectedTask != nil && !isSaving }

    private var primaryTitle: String {
        if case .startTimer = action { return "Start Timer" }
        return "Add Entry"
    }

    private var hint: String {
        let blank = hoursText.trimmingCharacters(in: .whitespaces).isEmpty
        guard blank else { return "Hours as 1:30 or 1.5." }
        return chosenDate == .today() ? "Leave hours empty to start a timer now." : "Enter the hours worked on this day."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * uiScale) {
            Text("Add time entry")
                .uiFont(.headline)

            ChoiceMenu(
                title: "Project",
                current: selectedProject.map(Self.label) ?? "No projects",
                items: projects,
                label: Self.label
            ) { project in
                projectID = project.id
                taskID = nil
            }

            ChoiceMenu(
                title: "Task",
                current: selectedTask?.name ?? "",
                items: selectedProject?.tasks ?? [],
                label: \.name
            ) { task in
                taskID = task.id
            }

            row("Date") {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Spacer(minLength: 0)
            }

            row("Hours") {
                TextField("1:30", text: $hoursText)
                    .textFieldStyle(.roundedBorder)
                    .uiFont(.callout, monospacedDigit: true)
                    .focused($isHoursFocused)
                    .onSubmit(submit)
            }

            row("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .uiFont(.callout)
                    .lineLimit(1...3)
            }

            Text(hint)
                .uiFont(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSubmit)
            }
            .uiFont(.callout)
        }
        .onAppear { isHoursFocused = true }
    }

    private static func label(_ project: ProjectTargets) -> String {
        guard let client = project.client, !client.name.isEmpty else { return project.project.name }
        return "\(client.name) · \(project.project.name)"
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8 * uiScale) {
            Text(title)
                .uiFont(.callout)
                .foregroundStyle(.secondary)
                .uiFrame(width: 56, alignment: .leading)
            content()
        }
    }

    private func submit() {
        guard let action, let project = selectedProject, let task = selectedTask else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = EntryDraft(
            target: project.target(task: task),
            date: chosenDate,
            action: action,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        isSaving = true
        Task {
            await onSubmit(draft)
            isSaving = false
        }
    }
}

/// A SwiftUI label, not a native popup, which ignores the panel's scale and colours.
private struct ChoiceMenu<Item: Identifiable>: View {
    @Environment(\.uiScale) private var uiScale

    let title: String
    let current: String
    let items: [Item]
    let label: (Item) -> String
    let choose: (Item) -> Void

    var body: some View {
        HStack(spacing: 8 * uiScale) {
            Text(title)
                .uiFont(.callout)
                .foregroundStyle(.secondary)
                .uiFrame(width: 56, alignment: .leading)
            Menu {
                ForEach(items) { item in
                    Button(label(item)) { choose(item) }
                }
            } label: {
                HStack(spacing: 4 * uiScale) {
                    Text(current)
                        .uiFont(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .uiFont(.caption2)
                        .opacity(0.6)
                }
                .uiPadding(.horizontal, 8)
                .uiPadding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6 * uiScale))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }
}
