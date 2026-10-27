import AppKit
import ScytheCore
import SwiftUI

/// The full window behind the menu bar item: every entry, searchable and chartable.
///
/// A menu bar app is an accessory, which has no Dock icon and no menu bar of its own.
/// While this window is open the app becomes a regular one, so the window can be found
/// again from the Dock and the main menu's shortcuts work; closing it goes back.
@MainActor
final class DesktopWindowController: NSObject, NSWindowDelegate {
    private let tracker: TimeTracker
    private let history: HistoryModel
    private let state: DesktopState
    private var window: NSWindow?

    init(tracker: TimeTracker, history: HistoryModel, state: DesktopState) {
        self.tracker = tracker
        self.history = history
        self.state = state
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task { await history.refresh() }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: DesktopRootView()
                .environment(tracker)
                .environment(history)
                .environment(state)
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
    @Environment(DesktopState.self) private var state
    @Environment(HistoryModel.self) private var history

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
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
