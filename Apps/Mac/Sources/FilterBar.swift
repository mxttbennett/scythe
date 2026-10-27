import ScytheCore
import SwiftUI

/// The query controls the explorer and the analytics share.
struct FilterBar: View {
    @Environment(HistoryModel.self) private var history
    @Environment(DesktopState.self) private var state

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
        }
        .controlSize(.regular)
        .popover(isPresented: $isChoosingRange, arrowEdge: .bottom) { customRange }
        .alert("Save Query", isPresented: $isNamingQuery) {
            TextField("Name", text: $queryName)
            Button("Save") { state.saveCurrentFilter(named: queryName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reopen this filter later from the sidebar.")
        }
    }

    private var periodLabel: String {
        switch state.filter.period {
        case .all: "All time"
        case .preset(let preset): preset.label
        case .custom(let range):
            "\(range.lowerBound.startOfDay().formatted(.dateTime.month(.abbreviated).day())) – \(range.upperBound.startOfDay().formatted(.dateTime.month(.abbreviated).day().year()))"
        }
    }

    private var periodMenu: some View {
        Menu {
            Button("All time") { state.filter.period = .all }
            Divider()
            ForEach(DatePreset.allCases) { preset in
                Button(preset.label) { state.filter.period = .preset(preset) }
            }
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

    var body: some View {
        Menu {
            ForEach(options) { option in
                Toggle(
                    option.name,
                    isOn: Binding(
                        get: { selection.contains(option.id) },
                        set: { isOn in
                            if isOn { selection.insert(option.id) } else { selection.remove(option.id) }
                        }
                    )
                )
            }
            if !selection.isEmpty {
                Divider()
                Button("Clear") { selection = [] }
            }
        } label: {
            Text(selection.isEmpty ? title : "\(title) · \(selection.count.formatted())")
        }
        .fixedSize()
        .disabled(options.isEmpty)
    }
}
