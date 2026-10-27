import AppKit
import OSLog
import ScytheCore

/// An AppKit entry point rather than a SwiftUI `App`.
///
/// Everything with a window is now owned directly — the status item, its popover,
/// the quick-entry panel, the settings window — because each needed behaviour
/// SwiftUI scenes do not offer: a menu bar button that acts on one click, and
/// windows that can be opened programmatically from a global hotkey. A SwiftUI
/// `App` would contribute only a scene that is never used.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    let tracker = AppDelegate.makeTracker()
    let hotKeyPreference = HotKeyPreference()
    let statusItemStyle = StatusItemStylePreference()
    let uiScale = UIScalePreference()
    let loginItem = LoginItemPreference()

    /// A demo instance runs beside the real one, on the documentation account —
    /// so a real screenshot can show the status item and its panel without
    /// touching anyone's timesheet. `SCYTHE_DEMO=1` in the environment selects
    /// it; debug builds only.
    static var isDemo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["SCYTHE_DEMO"] == "1"
        #else
        false
        #endif
    }

    private static func makeTracker() -> TimeTracker {
        #if DEBUG
        if isDemo {
            let scratch = URL.temporaryDirectory.appending(path: "scythe-demo-\(UUID().uuidString)")
            return TimeTracker(
                client: HarvestClient(
                    credentials: .init(accountID: "0", token: "demo"),
                    transport: DemoAccount()
                ),
                keychain: KeychainStore(service: "com.mxttbennett.scythe.demo-\(UUID().uuidString)"),
                snapshots: SnapshotStore(fileURL: scratch.appending(path: "snapshot.json")),
                queue: MutationQueue(fileURL: scratch.appending(path: "queue.json"))
            )
        }
        #endif
        return TimeTracker()
    }

    private static let log = Logger(subsystem: "com.mxttbennett.scythe", category: "hotkey")
    private static let presenceLog = Logger(subsystem: "com.mxttbennett.scythe", category: "presence")

    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var presence: PresenceMonitor?
    /// Absences waiting their turn to be asked about, oldest first.
    private var absences: [Absence] = []

    private lazy var quickEntry = QuickEntryController(
        tracker: tracker,
        uiScale: uiScale,
        openSettings: { [weak self] in self?.showSettings() }
    )
    private lazy var absencePrompt = AbsencePromptController(tracker: tracker, uiScale: uiScale)
    private lazy var historyModel: HistoryModel = {
        #if DEBUG
        if Self.isDemo {
            return HistoryModel(tracker: tracker, store: nil, fetcher: DemoHistory.fetcher, userID: 1)
        }
        #endif
        return HistoryModel(tracker: tracker)
    }()
    private lazy var desktopState = DesktopState(store: Self.isDemo ? nil : SavedQueryStore())
    private lazy var desktop = DesktopWindowController(
        tracker: tracker,
        history: historyModel,
        state: desktopState
    )
    private lazy var settings = SettingsWindowController(
        tracker: tracker,
        hotKeys: hotKeyPreference,
        statusItemStyle: statusItemStyle,
        loginItem: loginItem
    )

    /// True when the app was launched only to host a unit test bundle.
    private var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tests link against this app, so launching it must not claim a menu bar
        // slot, register a global hotkey or reach for the Keychain.
        guard !isHostingTests else { return }

        installMainMenu()

        statusItem = StatusItemController(
            tracker: tracker,
            style: statusItemStyle,
            uiScale: uiScale,
            openSettings: { [weak self] in self?.showSettings() },
            openDesktop: { [weak self] in self?.showDesktop() }
        )

        tracker.powerState = { PowerSource.current() }

        if Self.isDemo {
            // The demo account needs no keychain, so sync directly — and open the
            // panel from inside, because a capture must never click anything: a
            // synthetic click is exactly what the dismissal watchers listen for.
            Task {
                await tracker.sync()
                await statusItem?.showPanelForDemo()
            }
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["SCYTHE_DEMO_WINDOW"] == "1" {
                switch environment["SCYTHE_DEMO_SECTION"] {
                case "analytics": desktopState.section = .analytics
                case "timesheet": desktopState.section = .timesheet
                default: break
                }
                showDesktop()
            }
            #endif
            // No hotkey and no presence monitoring: the demo exists to be
            // photographed, not to compete with the real instance beside it.
            return
        }

        Task {
            await tracker.bootstrap()
            // Nothing in the menu bar is usable without a token, and the popover is
            // easy to miss on a first launch, so ask for one straight away.
            if tracker.connection == .needsCredentials {
                showSettings()
            }
        }

        hotKeyPreference.onChange = { [weak self] shortcut in
            self?.registerHotKey(shortcut)
        }
        registerHotKey(hotKeyPreference.shortcut)

        absencePrompt.onFinished = { [weak self] in self?.askAboutNextAbsence() }

        let presence = PresenceMonitor()
        presence.onAbsence = { [weak self] absence in self?.offerToTrim(absence) }
        presence.start()
        self.presence = presence
    }

    @objc func showSettings() {
        settings.show()
    }

    @objc func showDesktop() {
        desktop.show()
    }

    @objc private func zoomIn() { uiScale.zoomIn() }
    @objc private func zoomOut() { uiScale.zoomOut() }
    @objc private func resetZoom() { uiScale.reset() }

    /// An absence is only worth raising if a timer of ours ran through it.
    ///
    /// `trimmedHours(for:)` is nil when nobody was at this Mac at any point while
    /// that timer ran — a timer started on the web or a phone — and this machine
    /// has nothing to say about work it never saw.
    private func offerToTrim(_ absence: Absence) {
        // Queued, not substituted. Each absence describes a different stretch, and
        // answering only the most recent one silently bills every stretch before it:
        // a trim keeps everything earlier than where it starts.
        absences.append(absence)
        askAboutNextAbsence()
    }

    private func askAboutNextAbsence() {
        guard absencePrompt.pending == nil else { return }
        while !absences.isEmpty {
            let absence = absences.removeFirst()
            guard let running = tracker.runningEntry,
                  absence.trimmedHours(for: running) != nil
            else {
                Self.presenceLog.info("absence ignored: no timer of ours was running through it")
                continue
            }
            absencePrompt.present(absence, for: running)
            return
        }
    }

    /// Installs a main menu even though an accessory app never displays one.
    ///
    /// AppKit routes ⌘X/⌘C/⌘V/⌘A/⌘Z to text fields as *menu key equivalents* —
    /// NSTextField does not implement them itself. A SwiftUI `App` builds this menu
    /// for you; a hand-rolled AppKit entry point does not, and without it pasting a
    /// Harvest token into Settings silently does nothing, which is the very first
    /// thing anyone has to do.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Scythe",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        // On a US keyboard ⌘+ is typed as ⌘= without Shift, and "+" alone does not match it.
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetZoom), keyEquivalent: "0")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Scythe", action: #selector(showDesktop), keyEquivalent: "1")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    private func registerHotKey(_ shortcut: HotKeyShortcut) {
        // Release the old registration first: Carbon refuses a combination that is
        // still held, including the one being replaced.
        hotKey = nil
        // The Carbon callback is not isolated, so hop back to the main actor.
        hotKey = GlobalHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            Task { @MainActor in self?.quickEntry.toggle() }
        }
        let registered = hotKey != nil
        hotKeyPreference.isRegistered = registered
        // Carbon reports a taken combination by failing silently; Settings shows this,
        // but the log is the only trace when nobody is looking at Settings.
        Self.log.info(
            "quick entry hotkey \(shortcut.display, privacy: .public) registered: \(registered, privacy: .public)"
        )
    }
}
