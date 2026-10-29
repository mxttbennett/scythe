import ScytheCore
import SwiftUI

struct MenuBarPickerPopoverTrackingKey: EnvironmentKey {
    static let defaultValue: @MainActor (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var menuBarPickerPopoverTracking: @MainActor (Bool) -> Void {
        get { self[MenuBarPickerPopoverTrackingKey.self] }
        set { self[MenuBarPickerPopoverTrackingKey.self] = newValue }
    }
}

/// Takes the submit action as a closure, so the panel and the window each store a draft their own way.
struct AddEntryForm: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.uiScale) private var uiScale

    let onSubmit: (EntryDraft) async -> Void
    let onCancel: () -> Void

    @State private var projectID: Int?
    @State private var taskID: Int?
    @State private var clientID: Int?
    @State private var date: Date
    @State private var hoursText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var isChoosingProject = false
    @State private var isChoosingTask = false
    @State private var isChoosingClient = false
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
    private var clients: [Reference] {
        var seen = Set<Int>()
        return projects.compactMap(\.client).filter { seen.insert($0.id).inserted }
    }
    private var availableProjects: [ProjectTargets] {
        guard let clientID else { return projects }
        return projects.filter { $0.client?.id == clientID }
    }
    private var selectedClient: Reference? { clients.first { $0.id == clientID } }
    private var selectedProject: ProjectTargets? {
        availableProjects.first { $0.id == projectID } ?? availableProjects.first
    }
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

            SearchableChoiceMenu(
                title: "Client",
                current: selectedClient?.name ?? "All clients",
                items: clients,
                selectedID: clientID,
                searchPrompt: "Search clients",
                emptyMessage: "No clients match your search.",
                isPresented: $isChoosingClient,
                label: \.name,
                searchText: \.name,
                choose: chooseClient,
                clearSelection: clearClient,
                clearSelectionTitle: "All clients"
            )

            SearchableChoiceMenu(
                title: "Project",
                current: selectedProject.map(Self.label) ?? "No projects",
                items: availableProjects,
                selectedID: selectedProject?.id,
                searchPrompt: "Search projects",
                emptyMessage: availableProjects.isEmpty ? "No projects available for this client." : "No projects match your search.",
                isPresented: $isChoosingProject,
                label: Self.label,
                searchText: Self.label
            ) { project in
                clientID = project.client?.id
                projectID = project.id
                taskID = nil
                isChoosingTask = true
            }

            SearchableChoiceMenu(
                title: "Task",
                current: selectedTask?.name ?? "",
                items: selectedProject?.tasks ?? [],
                selectedID: selectedTask?.id,
                searchPrompt: "Search tasks",
                emptyMessage: selectedProject?.tasks.isEmpty == false ? "No tasks match your search." : "No tasks available for this project.",
                isPresented: $isChoosingTask,
                label: \.name,
                searchText: \.name
            ) { task in
                taskID = task.id
                Task { @MainActor in
                    await Task.yield()
                    isHoursFocused = true
                }
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
                .foregroundStyle(GlassInk.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    HStack(spacing: 6 * uiScale) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSaving ? "Saving…" : primaryTitle)
                    }
                }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel(isSaving ? "Saving entry" : primaryTitle)
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
                .foregroundStyle(GlassInk.secondary)
                .uiFrame(width: 56, alignment: .leading)
            content()
        }
    }

    private func submit() {
        guard !isSaving, let action, let project = selectedProject, let task = selectedTask else { return }
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

    private func chooseClient(_ client: Reference) {
        clientID = client.id
        let nextProjects = projects.filter { $0.client?.id == client.id }
        projectID = nextProjects.first?.id
        taskID = nil
        isChoosingProject = true
    }

    private func clearClient() {
        clientID = nil
        projectID = nil
        taskID = nil
    }
}
