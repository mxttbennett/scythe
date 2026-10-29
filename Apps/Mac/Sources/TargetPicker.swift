import ScytheCore
import SwiftUI

/// The list of projects a timer can be started on.
///
/// Purely presentational: which row is highlighted and what the keyboard does are
/// the host's business.
struct ProjectList: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TimeTracker.self) private var tracker

    var projects: [ProjectTargets]
    /// Index of the highlighted row, or nil when the selection is elsewhere.
    var highlighted: Int?
    @Binding var chosenTasks: [Int: Int]
    var maxVisible: Int = 6
    var emptyMessage: String
    var onStart: (TimerTarget) -> Void

    private var format: HoursFormat { HoursFormat(company: tracker.company) }

    var body: some View {
        if projects.isEmpty {
            Text(emptyMessage)
                .uiFont(.callout)
                .foregroundStyle(GlassInk.secondary)
                .uiPadding(.vertical, 8)
        } else {
            ScrollViewReader { proxy in
                SizedScrollView(maxHeight: CGFloat(maxVisible) * 40 * uiScale) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, entry in
                            TargetRow(
                                entry: entry,
                                isSelected: index == highlighted,
                                budget: tracker.budget(forProject: entry.id),
                                format: format,
                                task: binding(for: entry),
                                onStart: { start(entry) }
                            )
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: highlighted) { scrollToHighlighted(proxy) }
                // A narrower list can leave the highlight on row 0 with the scroll offset further down.
                .onChange(of: projects.map(\.id)) { scrollToHighlighted(proxy) }
            }
        }
    }

    private func scrollToHighlighted(_ proxy: ScrollViewProxy) {
        guard let highlighted, projects.indices.contains(highlighted) else { return }
        let id = projects[highlighted].id
        if reduceMotion {
            proxy.scrollTo(id)
        } else {
            withAnimation(.easeOut(duration: 0.14)) { proxy.scrollTo(id) }
        }
    }

    private func binding(for entry: ProjectTargets) -> Binding<Reference?> {
        Binding(
            get: { entry.task(chosenFrom: chosenTasks) },
            set: { chosenTasks[entry.id] = $0?.id }
        )
    }

    private func start(_ entry: ProjectTargets) {
        guard let task = entry.task(chosenFrom: chosenTasks) else { return }
        onStart(entry.target(task: task))
    }
}

extension ProjectTargets {
    /// The task a row shows: whatever was picked by hand, as long as it is still on
    /// offer, and otherwise the best-ranked one.
    func task(chosenFrom chosen: [Int: Int]) -> Reference? {
        guard let id = chosen[self.id], let match = tasks.first(where: { $0.id == id }) else {
            return tasks.first
        }
        return match
    }
}

/// A `ProjectList` that carries its own search field and keyboard, for the hotkey panel and the absence prompt.
struct TargetPicker: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TimeTracker.self) private var tracker

    /// What picking a row will do, when that is not obvious from where the list is.
    /// The absence prompt needs it; the hotkey panel does not.
    var title: String?
    var maxVisible: Int = 6
    var onStart: (TimerTarget) -> Void

    @State private var query = ""
    @State private var selection = 0
    @State private var chosenTasks: [Int: Int] = [:]
    @FocusState private var isSearching: Bool

    private var projects: [ProjectTargets] {
        tracker.orderedTargets.matching(query).groupedByProject()
    }

    var body: some View {
        let projects = projects
        VStack(alignment: .leading, spacing: 6 * uiScale) {
            if let title {
                Text(title)
                    .uiFont(.caption)
                    .foregroundStyle(GlassInk.secondary)
            }
            searchField
            ProjectList(
                projects: projects,
                highlighted: highlightedIndex(in: projects),
                chosenTasks: $chosenTasks,
                maxVisible: maxVisible,
                emptyMessage: query.isEmpty ? "No projects yet — sync with Harvest." : "Nothing matches “\(query)”.",
                onStart: onStart
            )
        }
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onChange(of: query) { selection = 0 }
        .onAppear { isSearching = true }
    }

    private var searchField: some View {
        HStack(spacing: 6 * uiScale) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GlassInk.secondary)
            TextField("Search clients, projects, tasks", text: $query)
                .textFieldStyle(.plain)
                .uiFont(.callout)
                .focused($isSearching)
                .onSubmit(activate)
            if !query.isEmpty {
                Button {
                    query = ""
                    isSearching = true
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
        .uiPadding(.horizontal, 8)
        .uiPadding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6 * uiScale))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: query.isEmpty)
    }

    // Clamped because a sync can shrink the list under a selection that was valid.
    private func highlightedIndex(in projects: [ProjectTargets]) -> Int {
        min(selection, max(projects.count - 1, 0))
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let projects = projects
        guard !projects.isEmpty else { return .ignored }
        selection = min(max(highlightedIndex(in: projects) + offset, 0), projects.count - 1)
        return .handled
    }

    private func activate() {
        let projects = projects
        let index = highlightedIndex(in: projects)
        guard projects.indices.contains(index),
              let task = projects[index].task(chosenFrom: chosenTasks)
        else { return }
        onStart(projects[index].target(task: task))
        selection = 0
    }
}

/// One project: its name and chosen task on the first line, its client and whatever
/// budget it has on the second.
///
/// Only the dropdown sits on the right-hand edge. The budget was there too, in a
/// column it had to share with the menu, which sized that column to whichever was
/// wider and left a small grey number stranded under a control. It reads as part of
/// the secondary line instead, on the separator "Client · Project" already uses.
private struct TargetRow: View {
    @Environment(\.uiScale) private var uiScale
    let entry: ProjectTargets
    let isSelected: Bool
    let budget: ProjectBudget?
    let format: HoursFormat
    @Binding var task: Reference?
    let onStart: () -> Void
    @State private var isChoosingTask = false

    private var selectedText: AnyShapeStyle {
        AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
    }

    private var secondaryText: AnyShapeStyle {
        isSelected
            ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor).opacity(0.9))
            : GlassInk.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1 * uiScale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * uiScale) {
                Text(entry.project.name)
                    .uiFont(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
                taskControl
            }
            detailLine
                .uiFont(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .uiPadding(.horizontal, 8)
        .uiPadding(.vertical, 4)
        .foregroundStyle(isSelected ? selectedText : AnyShapeStyle(.primary))
        .background(
            isSelected
                ? AnyShapeStyle(Color(nsColor: .selectedContentBackgroundColor))
                : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 5 * uiScale)
        )
        // The row cannot be a Button any more: the task dropdown lives inside it, and
        // a menu nested in a button never gets its own clicks.
        .contentShape(.rect)
        .onTapGesture(perform: onStart)
        // `.contain` rather than `.combine`, so the dropdown stays reachable instead
        // of being flattened into the row's label.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Start timer", onStart)
    }

    private var accessibilityLabel: String {
        var parts = [entry.project.name]
        if let client = entry.client?.name, !client.isEmpty { parts.append(client) }
        if let budget, let remaining = budget.formattedRemaining(format) {
            parts.append(budget.isOverBudget ? "\(remaining) over budget" : "\(remaining) of budget left")
        }
        return parts.joined(separator: ", ")
    }

    private var selectedTaskID: Binding<Int?> {
        Binding(
            get: { task?.id },
            set: { id in
                guard let id else { return }
                task = entry.tasks.first { $0.id == id }
            }
        )
    }

    /// A project with one task has nothing to choose, so it reads as a label rather
    /// than offering a menu that can only confirm itself.
    @ViewBuilder
    private var taskControl: some View {
        if entry.tasks.count <= 1 {
            Text(task?.name ?? "")
                .uiFont(.callout)
                .lineLimit(1)
        } else if entry.tasks.count > 8 {
            SearchableChoiceMenu(
                title: "Task",
                current: task?.name ?? "",
                items: entry.tasks,
                selectedID: task?.id,
                searchPrompt: "Search tasks",
                emptyMessage: "No tasks match your search.",
                isPresented: $isChoosingTask,
                label: \.name,
                searchText: \.name,
                choose: { task = $0 },
                showsTitle: false,
                usesButtonBackground: false,
                fillsAvailableWidth: false
            )
        } else {
            Menu {
                Picker("Task", selection: selectedTaskID) {
                    ForEach(entry.tasks) { option in
                        Text(option.name).tag(Optional(option.id))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 3 * uiScale) {
                    Text(task?.name ?? "")
                        .uiFont(.callout)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .uiFont(.caption2)
                        .fontWeight(.semibold)
                        .opacity(0.6)
                }
            }
            // The borderless style hands the label to AppKit, which draws it at the
            // control's own size and colour; a plain button keeps both under our control.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Task")
            .accessibilityValue(task?.name ?? "")
        }
    }

    /// The client, and the budget after it when there is one. A single flowing line
    /// rather than two aligned cells: these are both quiet facts about the project,
    /// and nothing here needs to line up with anything in the row above.
    private var detailLine: Text {
        let client = Text(entry.client?.name ?? "").foregroundStyle(secondaryText)
        guard let budget, let remaining = budget.formattedRemaining(format) else { return client }

        let figure = Text(budget.isOverBudget ? "\(remaining) over" : "\(remaining) left")
            .monospacedDigit()
            .foregroundStyle(budgetStyle(budget))
        guard entry.client?.name.isEmpty == false else { return figure }
        return Text("\(client) · \(figure)")
    }

    /// Overspend is worth a colour, but not on a selected row: red on the selection
    /// blue is unreadable, and the row is already the thing being pointed at.
    private func budgetStyle(_ budget: ProjectBudget) -> AnyShapeStyle {
        budget.isOverBudget && !isSelected ? AnyShapeStyle(.red) : secondaryText
    }
}
