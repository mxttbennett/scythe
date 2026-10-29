import ScytheCore
import SwiftUI

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
    @State private var clientID: Int?
    @State private var projectID: Int?
    @State private var taskID: Int?
    @State private var hoursAsOpened: String
    @State private var isConfirmingDelete = false
    @State private var isChoosingClient = false
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
        _clientID = State(initialValue: entry.client?.id)
        _projectID = State(initialValue: entry.project.id)
        _taskID = State(initialValue: entry.task.id)
    }

    /// The entry's own project stays on offer after it is unassigned, so opening the sheet never loses it.
    private var allProjects: [ProjectTargets] {
        let assigned = tracker.orderedProjects
        guard !assigned.contains(where: { $0.id == entry.project.id }) else { return assigned }
        return [ProjectTargets(project: entry.project, client: entry.client, tasks: [entry.task])] + assigned
    }

    private var clients: [Reference] {
        var seen = Set<Int>()
        return allProjects.compactMap(\.client).filter { seen.insert($0.id).inserted }
    }

    private var availableProjects: [ProjectTargets] {
        guard let clientID else { return allProjects }
        return allProjects.filter { $0.client?.id == clientID }
    }

    private var selectedClient: Reference? { clients.first { $0.id == clientID } }
    private var selectedProject: ProjectTargets? {
        availableProjects.first { $0.id == projectID } ?? availableProjects.first
    }

    private var taskChoices: [Reference] {
        let tasks = selectedProject?.tasks ?? []
        guard selectedProject?.id == entry.project.id, !tasks.contains(where: { $0.id == entry.task.id }) else { return tasks }
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
                LabeledContent("Client") {
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
                        clearSelectionTitle: "All clients",
                        showsTitle: false
                    )
                }
                LabeledContent("Project") {
                    SearchableChoiceMenu(
                        title: "Project",
                        current: selectedProject.map { label($0.client, $0.project) } ?? "No projects",
                        items: availableProjects,
                        selectedID: selectedProject?.id,
                        searchPrompt: "Search projects",
                        emptyMessage: availableProjects.isEmpty ? "No projects available for this client." : "No projects match your search.",
                        isPresented: $isChoosingProject,
                        label: { label($0.client, $0.project) },
                        searchText: { label($0.client, $0.project) },
                        choose: chooseProject,
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
                let choices = taskChoices
                if !choices.contains(where: { $0.id == taskID }) {
                    taskID = choices.first?.id
                }
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
            let targetChanged = selectedProject?.id != current.project.id || taskID != current.task.id
            let newTarget = targetChanged ? selectedProject.flatMap { project in
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

    private func chooseClient(_ client: Reference) {
        let previousProjectID = selectedProject?.id
        clientID = client.id
        let nextProjects = allProjects.filter { $0.client?.id == client.id }
        let next = nextProjects.first { $0.id == previousProjectID } ?? nextProjects.first
        projectID = next?.id
        taskID = next?.tasks.first?.id ?? (next?.id == entry.project.id ? entry.task.id : nil)
        isChoosingProject = true
    }

    private func clearClient() {
        let previousProjectID = selectedProject?.id
        clientID = nil
        let next = allProjects.first { $0.id == previousProjectID } ?? allProjects.first
        projectID = next?.id
        taskID = next?.tasks.first?.id ?? (next?.id == entry.project.id ? entry.task.id : nil)
    }

    private func chooseProject(_ project: ProjectTargets) {
        clientID = project.client?.id
        projectID = project.id
        taskID = project.tasks.first?.id ?? (project.id == entry.project.id ? entry.task.id : nil)
    }
}
