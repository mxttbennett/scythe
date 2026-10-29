import AppKit
import ScytheCore
import SwiftUI

/// The full window behind the menu bar item: every entry, searchable and chartable.
///
/// With the Dock icon off, the app is regular only while this window is open, so the Dock and the main menu reach it.
@MainActor
final class DesktopWindowController: NSObject, NSWindowDelegate {
    private let tracker: TimeTracker
    private let history: HistoryModel
    private let state: DesktopState
    private let dock: DockPreference
    private let dateFormat: EntryDateFormatPreference
    private var window: NSWindow?

    init(
        tracker: TimeTracker,
        history: HistoryModel,
        state: DesktopState,
        dock: DockPreference,
        dateFormat: EntryDateFormatPreference
    ) {
        self.tracker = tracker
        self.history = history
        self.state = state
        self.dock = dock
        self.dateFormat = dateFormat
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        dock.isDesktopWindowOpen = true
        dock.apply()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task { await history.refresh() }
    }

    func windowWillClose(_ notification: Notification) {
        state.isAddingEntry = false
        dock.isDesktopWindowOpen = false
        dock.apply()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: DesktopRootView()
                .environment(tracker)
                .environment(history)
                .environment(state)
                .environment(dateFormat)
        )
        // The window keeps the size the user gave it rather than following the content.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Scythe"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1120, height: 740))
        window.minSize = NSSize(width: 900, height: 540)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName("ScytheDesktop") { window.center() }
        window.setFrameAutosaveName("ScytheDesktop")
        return window
    }
}

struct DesktopRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DesktopState.self) private var state
    @Environment(HistoryModel.self) private var history
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        @Bindable var state = state
        let sidebarVisibility = Binding(
            get: { state.isSidebarVisible ? NavigationSplitViewVisibility.all : .detailOnly },
            set: { state.isSidebarVisible = $0 != .detailOnly }
        )
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            switch state.section {
            case .timesheet:
                TimesheetView()
                    .navigationTitle("Timesheet")
            case .explorer:
                queryable { ExplorerView() }
                    .navigationTitle("Explorer")
            case .analytics:
                queryable { AnalyticsView() }
                    .navigationTitle("Analytics")
            }
        }
        .task { await history.refresh() }
        .onChange(of: tracker.entries) { history.absorb(tracker.entries, on: tracker.day) }
        .opensLinearInDesktopApp()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.isAddingEntry = true
                } label: {
                    Label("New Entry", systemImage: "plus")
                }
                .help("Add a time entry (⌘N)")
            }
        }
        .overlay {
            if state.isAddingEntry {
                DismissibleModalOverlay(onDismiss: { state.isAddingEntry = false }) {
                    AddEntryForm(
                        initialDate: .today(),
                        onSubmit: { draft in
                            await history.addEntry(draft)
                            state.isAddingEntry = false
                        },
                        onCancel: { state.isAddingEntry = false }
                    )
                    .padding(20)
                    .frame(width: 440)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.isAddingEntry)
    }

    /// The explorer and the analytics answer the same question, so they share its controls.
    private func queryable<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        @Bindable var state = state
        return VStack(spacing: 0) {
            FilterBar()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            content()
        }
        .searchable(text: $state.filter.text, placement: .toolbar, prompt: "Search notes, projects, tasks")
    }

    private var sidebar: some View {
        List(
            selection: Binding<DesktopSection?>(
                get: { state.section },
                set: { if let section = $0 { state.section = section } }
            )
        ) {
            Section("Views") {
                Label("Explorer", systemImage: "list.bullet.rectangle").tag(DesktopSection.explorer)
                Label("Analytics", systemImage: "chart.bar.xaxis").tag(DesktopSection.analytics)
                Label("Timesheet", systemImage: "calendar").tag(DesktopSection.timesheet)
            }
            if !state.savedQueries.isEmpty {
                Section("Saved Queries") {
                    ForEach(state.savedQueries) { query in
                        Button {
                            state.open(query)
                        } label: {
                            Label(query.name, systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) { state.delete(query) }
                        }
                    }
                }
            }
        }
    }
}

/// Lets any view ask for the desktop window without knowing who owns it.
private struct OpenDesktopWindowKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var openDesktopWindow: @MainActor () -> Void {
        get { self[OpenDesktopWindowKey.self] }
        set { self[OpenDesktopWindowKey.self] = newValue }
    }
}
