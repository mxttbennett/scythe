import ScytheCore
import SwiftUI

/// The query controls the explorer and the analytics share.
struct FilterBar: View {
    @Environment(HistoryModel.self) private var history
    @Environment(DesktopState.self) private var state

    @AppStorage("explorerWrapNotes") private var wrapNotes = true
    @State private var isChoosingRange = false
    @State private var isNamingQuery = false
    @State private var queryName = ""
    @State private var customFrom = Date()
    @State private var customTo = Date()

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 8) {
            periodMenu
            FacetMenu(title: "Clients", options: history.clients, selection: $state.filter.clientIDs)
            FacetMenu(title: "Projects", options: history.projects, selection: $state.filter.projectIDs)
            FacetMenu(title: "Tasks", options: history.tasks, selection: $state.filter.taskIDs)

            Picker("Billable", selection: $state.filter.billable) {
                Text("All").tag(Bool?.none)
                Text("Billable").tag(Bool?.some(true))
                Text("Non-billable").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 0)

            if !state.filter.isEmpty {
                Button("Clear") { state.filter = EntryFilter() }
                Button("Save Query…") {
                    queryName = ""
                    isNamingQuery = true
                }
            }
            if !state.filter.isEmpty || !wrapNotes {
                Button("Reset defaults") {
                    state.filter = EntryFilter()
                    wrapNotes = true
                }
            }
        }
        .controlSize(.small)
        .popover(isPresented: $isChoosingRange, arrowEdge: .bottom) { customRange }
        .alert("Save Query", isPresented: $isNamingQuery) {
            TextField("Name", text: $queryName)
            Button("Save") { state.saveCurrentFilter(named: queryName) }
                .disabled(queryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reopen this filter later from the sidebar.")
        }
    }

    private var periodLabel: String {
        switch state.filter.period {
        case .all: return "All time"
        case .preset(let preset): return preset.label
        case .custom(let range):
            let first = range.lowerBound.startOfDay()
            let last = range.upperBound.startOfDay()
            if range.lowerBound == range.upperBound {
                return first.formatted(.dateTime.month(.abbreviated).day().year())
            } else if range.lowerBound.year == range.upperBound.year {
                return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
            } else {
                return "\(first.formatted(.dateTime.month(.abbreviated).day().year())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
            }
        }
    }

    private var periodMenu: some View {
        @Bindable var state = state
        return Menu {
            Picker("Date range", selection: $state.filter.period) {
                Text("All time").tag(Period.all)
                ForEach(DatePreset.allCases) { preset in
                    Text(preset.label).tag(Period.preset(preset))
                }
                if case .custom = state.filter.period {
                    Text(periodLabel).tag(state.filter.period)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Custom Range…") {
                let range = state.filter.period.range(today: .today(), weekStart: history.weekStart)
                customFrom = range?.lowerBound.startOfDay() ?? Date()
                customTo = range?.upperBound.startOfDay() ?? Date()
                isChoosingRange = true
            }
        } label: {
            Label(periodLabel, systemImage: "calendar")
        }
        .fixedSize()
        .accessibilityLabel("Date range")
        .accessibilityValue(periodLabel)
        .accessibilityHint("Choose a preset or custom range to filter entries.")
    }

    private var customRange: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("From", selection: $customFrom, displayedComponents: .date)
            DatePicker("To", selection: $customTo, displayedComponents: .date)
            HStack {
                Spacer()
                Button("Apply") {
                    let from = CalendarDate(customFrom)
                    let to = CalendarDate(customTo)
                    state.filter.period = .custom(min(from, to)...max(from, to))
                    isChoosingRange = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

/// A menu of checkable choices, titled with how many are on.
private struct FacetMenu: View {
    let title: String
    let options: [Reference]
    @Binding var selection: Set<Int>
    @State private var isPresented = false

    var body: some View {
        SearchableChoiceMenu(
            title: title,
            current: title,
            items: options,
            selectedID: nil,
            selectedIDs: selection,
            searchPrompt: "Search \(title.lowercased())",
            emptyMessage: "No \(title.lowercased()) match your search.",
            isPresented: $isPresented,
            label: \.name,
            searchText: \.name,
            choose: { option in
                if selection.contains(option.id) {
                    selection.remove(option.id)
                } else {
                    selection.insert(option.id)
                }
            },
            keepsOpenOnSelection: true,
            clearSelection: { selection = [] },
            showsTitle: false,
            fillsAvailableWidth: false
        )
        .fixedSize()
        .disabled(options.isEmpty)
        .accessibilityLabel(title)
        .accessibilityValue(selection.isEmpty ? "All" : "\(selection.count.formatted()) selected")
        .accessibilityHint("Choose one or more \(title.lowercased()) to filter entries.")
    }
}
