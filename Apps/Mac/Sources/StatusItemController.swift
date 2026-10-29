import AppKit
import ScytheCore
import SwiftUI

/// The menu bar item: a play/pause button on the left, everything else opens the
/// popover. In the icon-only style there is no everything else, so the whole item
/// opens the popover.
///
/// This is hand-rolled AppKit rather than SwiftUI's `MenuBarExtra` because a
/// `MenuBarExtra` has exactly one behaviour — any click opens its content — and the
/// point here is that pausing or resuming the current timer should take one click
/// and open nothing. Owning the `NSStatusItem` also means the popover can be shown
/// programmatically, which `MenuBarExtra` cannot do.
@MainActor
final class StatusItemController {
    private let tracker: TimeTracker
    private let stylePreference: StatusItemStylePreference
    private let uiScale: UIScalePreference
    private let openSettings: @MainActor () -> Void
    private let openDesktop: @MainActor () -> Void
    private let editEntryPanel: EditEntryPanelController
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanel
    private let content: NSHostingController<AnyView>
    private var dismissObservers: [any NSObjectProtocol] = []
    private var globalClickMonitor: Any?
    private var isTrackingOwnPickerPopover = false
    private var pickerPopoverRevision = 0
    /// True while this app is tracking a menu of its own — the picker's task
    /// dropdown, for one.
    ///
    /// The watchers below cannot tell our menu from anyone else's: HIToolbox
    /// broadcasts menu tracking system-wide, which is the whole reason it is
    /// observed, and the broadcast our dropdown causes is indistinguishable from
    /// Safari's. NSMenu posts locally when it begins and ends, and that is the
    /// signal that says the menu is ours.
    private var isTrackingOwnMenu = false
    /// Clicking the status item makes it key, which can close the panel a moment
    /// before the click action runs — without this the item would reopen what the
    /// same click just dismissed.
    private var lastHiddenAt = Date.distantPast

    /// Width of the leading icon, and so of the region that toggles the timer.
    private let iconRegionWidth: CGFloat = 24

    init(
        tracker: TimeTracker,
        history: HistoryModel,
        style: StatusItemStylePreference,
        uiScale: UIScalePreference,
        openSettings: @escaping @MainActor () -> Void,
        openDesktop: @escaping @MainActor () -> Void
    ) {
        self.tracker = tracker
        self.stylePreference = style
        self.uiScale = uiScale
        self.openSettings = openSettings
        self.openDesktop = openDesktop
        editEntryPanel = EditEntryPanelController(tracker: tracker, history: history, uiScale: uiScale)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        content = NSHostingController(rootView: AnyView(EmptyView()))
        content.sizingOptions = [.preferredContentSize]
        panel = MenuBarPanel(contentViewController: content)
        content.rootView = AnyView(
            DayView()
                .environment(tracker)
                .environment(history)
                .environment(\.openSettingsWindow, openSettings)
                .environment(\.openDesktopWindow, openDesktop)
                .environment(\.openEntryEditor) { [weak self] entry in
                    self?.presentEditor(for: entry)
                }
                .environment(\.menuBarPickerPopoverTracking) { [weak self] in
                    self?.pickerPopoverDidChange($0)
                }
                .glassSurface()
                .environment(uiScale)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.imagePosition = .imageLeading
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        observeTracker()
        uiScale.observe { [weak self] in self?.refitPanel() }
    }

    // MARK: - Rendering

    /// Redraws now and again whenever anything the drawing reads changes.
    private func observeTracker() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            // onChange fires before the value is applied, so re-read on the next turn.
            Task { @MainActor in self?.observeTracker() }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let activity = tracker.activity

        button.image = Self.icon(for: activity, style: stylePreference.style)
        button.attributedTitle = title(for: activity)
        button.toolTip = toolTip(for: activity)
        // Spoken, not read as digits: "0:19" becomes "zero nineteen" otherwise. The
        // label describes state rather than promising an action, because an
        // accessibility press cannot hit the icon region and so opens the panel.
        button.setAccessibilityLabel(StatusItemAccessibility.label(for: activity))
        button.setAccessibilityValue(
            StatusItemAccessibility.value(
                for: activity,
                style: stylePreference.style,
                isToday: tracker.isToday,
                totalHours: tracker.totalHours,
                now: tracker.now
            )
        )
    }

    /// The glyph, tinted with the accent colour while a timer runs.
    ///
    /// Colour is how macOS itself says a menu bar extra is doing something —
    /// Screen Mirroring turns blue while it mirrors — and the accent colour is the
    /// one the user chose for exactly that. The tint is on the glyph alone: it is
    /// what carries the state, and a whole menu bar entry in colour is louder than
    /// a running timer warrants. It is never the only signal, since the symbol
    /// already differs between the three states.
    ///
    /// A status bar button paints a *template* image in the menu bar's own text
    /// colour and ignores `contentTintColor` doing it, so the tinted glyph has to
    /// arrive already coloured and marked as not a template.
    static func icon(for activity: TimeTracker.Activity, style: StatusItemStyle = .time) -> NSImage? {
        let base = NSImage(systemSymbolName: symbolName(for: activity), accessibilityDescription: nil)
        let image: NSImage?
        if style == .stacked {
            image = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            if let image {
                image.size = NSSize(width: image.size.width * 0.85, height: image.size.height * 0.85)
            }
        } else {
            image = base
        }
        guard case .running = activity, let image else { return image }
        // Drawn on demand rather than once, so the accent the user is using now is
        // the one that gets read.
        let tinted = NSImage(size: image.size, flipped: false) { bounds in
            image.draw(in: bounds)
            NSColor.controlAccentColor.set()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private static func symbolName(for activity: TimeTracker.Activity) -> String {
        switch activity {
        case .running: "pause.fill"
        case .recent: "play.fill"
        case .idle: "timer"
        }
    }

    private func title(for activity: TimeTracker.Activity) -> NSAttributedString {
        guard let entry = activity.entry else { return NSAttributedString(string: "") }
        let format = HoursFormat(company: tracker.company)
        return StatusItemTitle.attributed(
            style: stylePreference.style,
            project: entry.project.name,
            hours: entry.hours(asOf: tracker.now).formattedHours(format),
            total: tracker.totalHours.formattedHours(format),
            isToday: tracker.isToday
        )
    }

    private func toolTip(for activity: TimeTracker.Activity) -> String {
        guard let entry = activity.entry else { return "Scythe — click for today’s entries" }
        let subject = "\(entry.project.name): \(entry.task.name)"
        let style = stylePreference.style
        guard style != .iconOnly else { return "\(subject)\nClick for today’s entries." }
        let action = entry.isRunning ? "Pause" : "Resume"
        let region = style == .projectAndTime ? "name" : "time"
        return "\(subject)\n\(action) — click the icon. Click the \(region) for today’s entries."
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        let activity = tracker.activity

        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(for: activity)
            return
        }

        // With nothing to toggle, or only the icon showing, there is no second region,
        // so the whole item opens the popover.
        guard let entry = activity.entry, stylePreference.style != .iconOnly, isIconClick(on: button) else {
            togglePopover()
            return
        }

        Task { await tracker.toggle(entry) }
    }

    /// Asks the pointer where it is, not the event.
    ///
    /// macOS 27 delivers a status item's clicks with `locationInWindow` pinned to the
    /// item's centre wherever they landed — the underlying `CGEvent` says the same —
    /// so the event put every click in the text and none on the icon.
    private func isIconClick(on button: NSStatusBarButton) -> Bool {
        guard NSApp.currentEvent?.type == .leftMouseUp, let window = button.window else { return false }
        // Only x is compared: a pointer thrown against the top of the screen is above
        // the button's bounds, and that is the easiest way there is to hit the icon.
        let pointer = button.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return pointer.x <= iconRegionWidth
    }

    /// The conventional menu bar extra right-click menu — and the only route to
    /// pause, resume or quit that does not require a mouse aimed at a 24-point strip.
    private func showMenu(for activity: TimeTracker.Activity) {
        // Attaching the menu makes the next click open it; clearing it afterwards
        // keeps left-click on the button's own action.
        statusItem.menu = Self.menu(for: activity, target: self)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    static func menu(for activity: TimeTracker.Activity, target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        if let entry = activity.entry {
            let title = entry.isRunning ? "Pause \(entry.task.name)" : "Resume \(entry.task.name)"
            let item = NSMenuItem(title: title, action: #selector(StatusItemController.toggleTimer), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let open = NSMenuItem(title: "Open Scythe", action: #selector(StatusItemController.openDesktopItem), keyEquivalent: "")
        open.target = target
        menu.addItem(open)

        let settings = NSMenuItem(title: "Settings…", action: #selector(StatusItemController.openSettingsItem), keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Scythe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        return menu
    }

    @objc private func toggleTimer() {
        guard let entry = tracker.activity.entry else { return }
        Task { await tracker.toggle(entry) }
    }

    @objc private func openSettingsItem() {
        openSettings()
    }

    @objc private func openDesktopItem() {
        openDesktop()
    }

    private func presentEditor(for entry: TrackedEntry) {
        hidePanel()
        editEntryPanel.present(entry)
    }

    // MARK: - Panel

    func togglePopover() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    /// Demo instances only: the panel, opened the way a person would see it.
    ///
    /// Twice over, because a cold panel positions itself from a zero size —
    /// SwiftUI reports none until it has laid out — so the first show is only
    /// the layout pass. The middle sleep outlasts `showPanel`'s reopen guard.
    func showPanelForDemo() async {
        showPanel()
        try? await Task.sleep(for: .milliseconds(400))
        hidePanel()
        try? await Task.sleep(for: .milliseconds(300))
        showPanel()
    }

    /// Size before positioning: the panel hangs from the menu bar downwards, so its
    /// origin depends on how tall the content turns out to be.
    private func fitPanel(under button: NSStatusBarButton, in buttonWindow: NSWindow) {
        panel.fitToContent()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.setFrameOrigin(origin(below: anchor))
    }

    private func refitPanel() {
        guard panel.isVisible, let button = statusItem.button, let buttonWindow = button.window else { return }
        fitPanel(under: button, in: buttonWindow)
    }

    private func showPanel() {
        guard Date().timeIntervalSince(lastHiddenAt) > 0.2 else { return }
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        fitPanel(under: button, in: buttonWindow)

        // An accessory app is not active, and an inactive app's window cannot take
        // key input — the search field would swallow every keystroke. Activation also
        // raises every other window the app has, which a click here must not do.
        if Self.shouldActivate(over: NSApp.windows, excluding: panel) {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        // Arm dismissal on the next turn of the run loop. Armed synchronously, the
        // very click that opened the panel can still be in flight and close it again.
        Task { @MainActor in
            guard self.panel.isVisible else { return }
            self.installDismissWatchers()
        }
        Task { await tracker.sync() }
    }

    /// False while a desktop or settings window is open, so the panel opens without pulling it forward.
    static func shouldActivate(over windows: [NSWindow], excluding panel: NSWindow) -> Bool {
        !windows.contains { $0 !== panel && $0.isVisible && $0.canBecomeMain }
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastHiddenAt = Date()
        removeDismissWatchers()
    }

    /// Menu bar panels sit just under the bar, centred on their item, and never hang
    /// off the edge of the screen.
    private func origin(below anchor: NSRect) -> NSPoint {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        let margin: CGFloat = 8

        let x = min(
            max(anchor.midX - size.width / 2, visible.minX + margin),
            visible.maxX - size.width - margin
        )
        return NSPoint(x: x, y: anchor.minY - size.height - 2)
    }

    /// Menu bar panels close as soon as attention moves anywhere else.
    ///
    /// Losing key focus is not enough on its own: another app's menu bar menu opens
    /// inside its own event loop, and this panel never resigns key while that
    /// happens. HIToolbox broadcasts menu tracking system-wide, which covers those;
    /// a global click monitor covers menu bar extras that are panels rather than
    /// menus, since those produce an ordinary mouse-down in another process.
    ///
    /// Both are indiscriminate, so the menu and picker report their tracking state
    /// while open.
    private func installDismissWatchers() {
        // A demo instance exists to be photographed, not used: while the person
        // whose machine it is keeps working, every one of their clicks lands in
        // another process and would close the panel mid-capture.
        guard !AppDelegate.isDemo else { return }
        guard dismissObservers.isEmpty else { return }
        // A sheet on the panel — a delete confirmation, the resume-on-today offer —
        // makes the panel resign key to its own dialog, which must not read as
        // attention moving away: hiding the panel would take the question with it.
        let close: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isTrackingOwnMenu, !self.isTrackingOwnPickerPopover,
                      self.panel.attachedSheet == nil
                else { return }
                self.hidePanel()
            }
        }

        dismissObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isTrackingOwnMenu = true }
            }
        )
        dismissObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.endMenuTracking() }
            }
        )

        dismissObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main, using: close
            )
        )
        dismissObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.HIToolbox.beginMenuTrackingNotification"),
                object: nil,
                queue: .main,
                using: close
            )
        )

        // Global monitors see only other applications' events, so clicking inside
        // this panel or on the status item does not trip it.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isTrackingOwnMenu, !self.isTrackingOwnPickerPopover,
                      self.panel.attachedSheet == nil
                else { return }
                self.hidePanel()
            }
        }
    }

    /// Stops treating a menu as ours, a run loop turn late: the system-wide broadcast
    /// for the menu that just closed can still be in flight behind the local
    /// notification that closed it, and it would land on a cleared flag and shut the
    /// panel that the menu belongs to.
    private func endMenuTracking() {
        Task { @MainActor [weak self] in
            self?.isTrackingOwnMenu = false
        }
    }

    private func pickerPopoverDidChange(_ isPresented: Bool) {
        pickerPopoverRevision += 1
        let revision = pickerPopoverRevision
        if isPresented {
            isTrackingOwnPickerPopover = true
            return
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.pickerPopoverRevision == revision
            else { return }
            self.isTrackingOwnPickerPopover = false
            guard
                  !self.isTrackingOwnMenu,
                  self.panel.attachedSheet == nil,
                  !self.panel.isKeyWindow
            else { return }
            self.hidePanel()
        }
    }

    private func removeDismissWatchers() {
        for observer in dismissObservers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        dismissObservers.removeAll()
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        // Never leave this set: a stuck flag is a panel that will not close.
        isTrackingOwnMenu = false
        isTrackingOwnPickerPopover = false
        pickerPopoverRevision += 1
    }
}
