import AppKit

/// Whether Scythe keeps an icon in the Dock.
///
/// The bundle starts as an accessory (`LSUIElement`) so a hidden icon never flashes at launch.
@MainActor
@Observable
final class DockPreference {
    private static let defaultsKey = "showInDock"
    private static let badgeKey = "showDockBadge"
    private static let backgroundBadgeKey = "keepDockBadgeUpdatedInBackground"

    var showInDock: Bool {
        didSet {
            guard showInDock != oldValue else { return }
            defaults.set(showInDock, forKey: Self.defaultsKey)
            onChange?()
        }
    }

    var showElapsedBadge: Bool {
        didSet {
            guard showElapsedBadge != oldValue else { return }
            defaults.set(showElapsedBadge, forKey: Self.badgeKey)
            onChange?()
        }
    }

    var keepBadgeUpdatedInBackground: Bool {
        didSet {
            guard keepBadgeUpdatedInBackground != oldValue else { return }
            defaults.set(keepBadgeUpdatedInBackground, forKey: Self.backgroundBadgeKey)
            onChange?()
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var isDesktopWindowOpen = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showInDock = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
        showElapsedBadge = defaults.object(forKey: Self.badgeKey) as? Bool ?? false
        keepBadgeUpdatedInBackground = defaults.object(forKey: Self.backgroundBadgeKey) as? Bool ?? false
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
