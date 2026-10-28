import AppKit
import ScytheCore
import SwiftUI

@MainActor
final class EditEntryPanelController {
    private let tracker: TimeTracker
    private let history: HistoryModel
    private let uiScale: UIScalePreference
    private(set) var window: NSPanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(tracker: TimeTracker, history: HistoryModel, uiScale: UIScalePreference) {
        self.tracker = tracker
        self.history = history
        self.uiScale = uiScale
    }

    func present(_ entry: TrackedEntry) {
        dismiss()
        let shape = RoundedRectangle(cornerRadius: 14)
        let root = EditEntrySheet(entry: entry, format: HoursFormat(company: tracker.company), asOf: tracker.now) { [weak self] in
            self?.dismiss()
        }
        .environment(history)
        .environment(tracker)
        .environment(uiScale)
        .padding(20)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor), in: shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)

        let hosting = NSHostingController(rootView: AnyView(root))
        hosting.sizingOptions = []
        let panel = EditEntryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.contentViewController = hosting
        window = panel

        hosting.view.layoutSubtreeIfNeeded()
        let height = hosting.view.fittingSize.height
        panel.setContentSize(NSSize(width: 560, height: max(height, 500)))
        panel.centreOnScreenUnderPointer()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Task { @MainActor [weak self, weak panel] in
            await Task.yield()
            guard let self, let panel, self.window === panel else { return }
            self.installDismissWatchers()
        }
    }

    func dismiss() {
        guard let window else { return }
        self.window = nil
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        window.orderOut(nil)
    }

    private func installDismissWatchers() {
        let closeIfOutside: @MainActor (NSEvent) -> Void = { [weak self] _ in
            self?.dismissIfClickingOutside()
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            Task { @MainActor in closeIfOutside(event) }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            Task { @MainActor in closeIfOutside(event) }
            return event
        }
    }

    func dismissIfClickingOutside(at point: NSPoint = NSEvent.mouseLocation) {
        guard let window, window.isVisible,
              !window.frame.contains(point)
        else { return }
        dismiss()
    }
}

private final class EditEntryPanel: NSPanel {
    var onCancel: (@MainActor () -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct OpenEntryEditorKey: EnvironmentKey {
    static let defaultValue: (@MainActor (TrackedEntry) -> Void)? = nil
}

extension EnvironmentValues {
    var openEntryEditor: (@MainActor (TrackedEntry) -> Void)? {
        get { self[OpenEntryEditorKey.self] }
        set { self[OpenEntryEditorKey.self] = newValue }
    }
}
