import AppKit

/// Whether Scythe keeps an icon in the Dock.
///
/// The bundle starts as an accessory (`LSUIElement`) so a hidden icon never flashes at launch.
@MainActor
@Observable
final class DockPreference {
    private static let defaultsKey = "showInDock"

    var showInDock: Bool {
        didSet {
            guard showInDock != oldValue else { return }
            defaults.set(showInDock, forKey: Self.defaultsKey)
            onChange?()
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var isDesktopWindowOpen = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showInDock = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        showInDock || isDesktopWindowOpen ? .regular : .accessory
    }

    /// Dropping to an accessory deactivates the app, which would bury the Settings window.
    func apply() {
        let wasActive = NSApp.isActive
        NSApp.setActivationPolicy(activationPolicy)
        if wasActive { NSApp.activate(ignoringOtherApps: true) }
    }
}
