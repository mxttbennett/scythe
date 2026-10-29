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
    @State private var date: Date
    @State private var hoursText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var isChoosingProject = false
    @State private var isChoosingTask = false
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

            SearchableChoiceMenu(
                title: "Project",
                current: selectedProject.map(Self.label) ?? "No projects",
                items: projects,
                selectedID: selectedProject?.id,
                searchPrompt: "Search projects",
                emptyMessage: projects.isEmpty ? "No projects available." : "No projects match your search.",
                isPresented: $isChoosingProject,
                label: Self.label,
                searchText: Self.label
            ) { project in
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
}

enum ChoiceSearch {
    static func filter<Item>(
        _ items: [Item],
        query: String,
        searchText: (Item) -> String
    ) -> [Item] {
        let words = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let text = fold(searchText(item))
            return words.allSatisfy { text.contains($0) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

struct SearchableChoiceMenu<Item: Identifiable>: View where Item.ID: Hashable {
    @Environment(\.uiScale) private var uiScale
    @Environment(\.menuBarPickerPopoverTracking) private var trackPopover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let current: String
    let items: [Item]
    let selectedID: Item.ID?
    var selectedIDs: Set<Item.ID>? = nil
    let searchPrompt: String
    let emptyMessage: String
    @Binding var isPresented: Bool
    let label: (Item) -> String
    let searchText: (Item) -> String
    let choose: (Item) -> Void
    var keepsOpenOnSelection = false
    var clearSelection: (() -> Void)? = nil
    var showsTitle = true
    var usesButtonBackground = true
    var fillsAvailableWidth = true
    var anchorSystemImage: String? = nil
    @State private var query = ""
    @State private var highlightedID: Item.ID?
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [Item] {
        ChoiceSearch.filter(items, query: query, searchText: searchText)
    }

    private var highlightedIndex: Int {
        guard let highlightedID,
              let index = filteredItems.firstIndex(where: { $0.id == highlightedID })
        else { return 0 }
        return index
    }

    var body: some View {
        HStack(spacing: 8 * uiScale) {
            if showsTitle {
                Text(title)
                    .uiFont(.callout)
                    .foregroundStyle(GlassInk.secondary)
                    .uiFrame(width: 56, alignment: .leading)
            }
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 6 * uiScale) {
                    if let anchorSystemImage {
                        Label(anchorTitle, systemImage: anchorSystemImage)
                            .uiFont(.callout)
                            .lineLimit(1)
                    } else {
                        Text(anchorTitle)
                            .uiFont(.callout)
                            .lineLimit(1)
                    }
                    if anchorSystemImage == nil {
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .uiFont(.caption2)
                            .opacity(0.6)
                    }
                }
                .uiPadding(.horizontal, usesButtonBackground ? 8 : 0)
                .uiPadding(.vertical, usesButtonBackground ? 4 : 0)
                .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
                .background(
                    usesButtonBackground ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6 * uiScale)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(anchorTitle)
            .help(anchorTitle)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8 * uiScale) {
                    HStack(spacing: 6 * uiScale) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(GlassInk.secondary)
                        TextField(searchPrompt, text: $query)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .onSubmit(chooseHighlighted)
                        if !query.isEmpty {
                            Button {
                                query = ""
                                isSearchFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(GlassInk.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear search")
                            .accessibilityLabel("Clear search")
                            .transition(.opacity)
                        }
                    }
                    .uiPadding(.horizontal, 9)
                    .uiPadding(.vertical, 7)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8 * uiScale))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: query.isEmpty)

                    if filteredItems.isEmpty {
                        Text(emptyMessage)
                            .uiFont(.callout)
                            .foregroundStyle(GlassInk.secondary)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 2 * uiScale) {
                                    ForEach(filteredItems) { item in
                                        choiceRow(item)
                                            .id(item.id)
                                    }
                                }
                            }
                            .frame(maxHeight: 260 * uiScale)
                            .onChange(of: highlightedID) { scrollToHighlight(proxy) }
                        }
                    }

                    if let clearSelection, selectedIDs?.isEmpty == false {
                        Divider()
                        Button("Clear Selection") {
                            clearSelection()
                            isSearchFocused = true
                        }
                            .buttonStyle(.plain)
                            .uiFont(.callout)
                            .foregroundStyle(GlassInk.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .uiPadding(.horizontal, 8)
                    }
                }
                .uiPadding(10)
                .frame(width: 320 * uiScale)
                .onKeyPress(.downArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -1) }
                .onKeyPress(.escape, phases: .down) { _ in
                    if query.isEmpty {
                        isPresented = false
                    } else {
                        query = ""
                        isSearchFocused = true
                    }
                    return .handled
                }
                .onAppear { isSearchFocused = true }
            }
            .onChange(of: items.map(\.id)) { _, _ in
                guard isPresented else { return }
                if !filteredItems.contains(where: { $0.id == highlightedID }) {
                    highlightedID = filteredItems.first?.id
                }
            }
            .onChange(of: query) { _, _ in
                highlightedID = filteredItems.first?.id
            }
            .onChange(of: isPresented) { _, presented in
                trackPopover(presented)
                isSearchFocused = presented
                guard presented else { return }
                query = ""
                highlightedID = items.first?.id
            }
        }
    }

    private var anchorTitle: String {
        guard let selectedIDs else { return current }
        return selectedIDs.isEmpty ? title : "\(title) · \(selectedIDs.count.formatted())"
    }

    private func choiceRow(_ item: Item) -> some View {
        let isHighlighted = item.id == highlightedID
        let isSelected = selectedIDs?.contains(item.id) ?? (item.id == selectedID)
        return Button {
            select(item)
        } label: {
            HStack(spacing: 8 * uiScale) {
                Image(systemName: "checkmark")
                    .uiFont(.caption)
                    .frame(width: 12 * uiScale)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(label(item))
                    .uiFont(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .uiPadding(.horizontal, 8)
            .uiPadding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isHighlighted ? Color.white : Color.primary)
            .background(
                isHighlighted ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6 * uiScale)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(item))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(label(item))
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard !filteredItems.isEmpty else { return .ignored }
        let index = min(max(highlightedIndex + offset, 0), filteredItems.count - 1)
        highlightedID = filteredItems[index].id
        return .handled
    }

    private func chooseHighlighted() {
        guard filteredItems.indices.contains(highlightedIndex) else { return }
        select(filteredItems[highlightedIndex])
    }

    private func select(_ item: Item) {
        if !keepsOpenOnSelection { isPresented = false }
        choose(item)
        if keepsOpenOnSelection { isSearchFocused = true }
    }

    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard filteredItems.indices.contains(highlightedIndex) else { return }
        let id = filteredItems[highlightedIndex].id
        if reduceMotion {
            proxy.scrollTo(id)
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                proxy.scrollTo(id)
            }
        }
    }
}
