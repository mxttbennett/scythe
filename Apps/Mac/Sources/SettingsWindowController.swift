import AppKit
import ScytheCore
import SwiftUI

/// Opens the settings window.
///
/// `SettingsLink` and the `Settings` scene do not work from inside a
/// `MenuBarExtra` popover — the link renders as inert text and the click goes
/// nowhere — and neither is reachable at all from the quick-entry panel, which
/// lives outside the scene graph. Owning the window directly makes both paths
/// behave the same.
@MainActor
final class SettingsWindowController {
    private let tracker: TimeTracker
    private let hotKeys: HotKeyPreference
    private let statusItemStyle: StatusItemStylePreference
    private let loginItem: LoginItemPreference
    private let dock: DockPreference
    private var window: NSWindow?

    init(
        tracker: TimeTracker,
        hotKeys: HotKeyPreference,
        statusItemStyle: StatusItemStylePreference,
        loginItem: LoginItemPreference,
        dock: DockPreference
    ) {
        self.tracker = tracker
        self.hotKeys = hotKeys
        self.statusItemStyle = statusItemStyle
        self.loginItem = loginItem
        self.dock = dock
    }

    func show() {
        // Cheap, and the window is about to show a switch that must not lie.
        loginItem.refresh()
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        // A menu bar app is an accessory: without this the window opens behind
        // whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView()
                .environment(tracker)
                .environment(hotKeys)
                .environment(statusItemStyle)
                .environment(loginItem)
                .environment(dock)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Scythe Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .normal
        return window
    }
}

/// Lets any view ask for the settings window without knowing who owns it.
private struct OpenSettingsWindowKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var openSettingsWindow: @MainActor () -> Void {
        get { self[OpenSettingsWindowKey.self] }
        set { self[OpenSettingsWindowKey.self] = newValue }
    }
}
