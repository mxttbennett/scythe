import AppKit
import SheavesCore
import SwiftUI

/// The Spotlight-style panel the global hotkey summons.
///
/// A floating panel rather than the menu bar popover, because SwiftUI's
/// `MenuBarExtra` cannot be opened programmatically — and a centred panel is a
/// better target for a hotkey anyway.
@MainActor
final class QuickEntryController {
    private let tracker: TimeTracker
    private let uiScale: UIScalePreference
    private let openSettings: @MainActor () -> Void
    private var panel: NSPanel?
    private var content: NSHostingController<AnyView>?

    init(tracker: TimeTracker, uiScale: UIScalePreference, openSettings: @escaping @MainActor () -> Void) {
        self.tracker = tracker
        self.uiScale = uiScale
        self.openSettings = openSettings
        uiScale.observe { [weak self] in self?.refit() }
    }

    private func refit() {
        guard let panel, panel.isVisible else { return }
        panel.fitToContent()
        centre(panel)
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // Size before positioning: the panel is centred, so where it goes depends on
        // how tall the content turns out to be.
        if let content {
            content.view.layoutSubtreeIfNeeded()
            let fitted = content.view.fittingSize
            if fitted.width > 0, fitted.height > 0 {
                panel.setContentSize(fitted)
            }
        }
        centre(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Task { await tracker.sync() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
            // Borderless, not titled: a titled window reserves and paints a titlebar
            // strip even with the title hidden and the bar transparent, which showed
            // up as unexplained whitespace above the content. This also matches the
            // menu bar panel, which had no business looking like a different app.
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

        let root = QuickEntryView(onDismiss: { [weak self] in self?.hide() })
            .environment(tracker)
            .environment(\.openSettingsWindow) { [weak self] in
                self?.hide()
                self?.openSettings()
            }
            .glassSurface()
            .environment(uiScale)

        let hosting = NSHostingController(rootView: AnyView(root))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        content = hosting
        return panel
    }

    private func centre(_ panel: NSPanel) {
        panel.centreOnScreenUnderPointer()
    }
}

extension NSWindow {
    /// Centres on the screen the user is actually looking at.
    ///
    /// Not `NSScreen.main`: that is the screen holding the *key window*, and an
    /// accessory app has none when a hotkey fires from another app — so it silently
    /// falls back to the primary display and the panel opens on the wrong monitor.
    /// The pointer is the best available signal for where the user is working.
    func centreOnScreenUnderPointer() {
        let pointer = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let screen = target?.visibleFrame else { return }
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: screen.midX - size.width / 2,
                // Slightly above centre reads better than dead centre, as Spotlight does.
                y: screen.midY - size.height / 2 + screen.height * 0.1
            )
        )
    }
}

/// A panel has to opt in to becoming key, or the search field never takes keystrokes.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

struct QuickEntryView: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(TimeTracker.self) private var tracker
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * uiScale) {
            header

            if tracker.connection == .needsCredentials {
                ConnectPrompt()
            } else {
                TargetPicker(maxVisible: 5) { target in
                    Task { await tracker.start(target) }
                    onDismiss()
                }
            }

            Divider()
            SyncStatusLabel()
                .uiFont(.caption)
        }
        .uiPadding(16)
        .uiFrame(width: 520, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand(perform: onDismiss)
    }

    @ViewBuilder
    private var header: some View {
        if let running = tracker.runningEntry {
            HStack(spacing: 8 * uiScale) {
                Image(systemName: "timer")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(running.task.name).uiFont(.callout).fontWeight(.semibold)
                    Text(running.target.projectLabel).uiFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(running.hours(asOf: tracker.now).formattedHours(HoursFormat(company: tracker.company)))
                    .uiFont(.callout, monospacedDigit: true)
                Button("Stop") {
                    Task { await tracker.stopRunning() }
                    onDismiss()
                }
            }
            .uiPadding(.bottom, 2)
        } else {
            Text("Nothing running · \(tracker.totalHours.formattedHours(HoursFormat(company: tracker.company))) today")
                .uiFont(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
