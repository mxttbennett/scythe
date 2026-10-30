import AppKit
import ScytheCore
import SwiftUI

struct SettingsView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(HotKeyPreference.self) private var hotKeys
    @Environment(StatusItemStylePreference.self) private var statusItemStyle
    @Environment(LoginItemPreference.self) private var loginItem
    @Environment(DockPreference.self) private var dock

    @State private var accountID = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var isConfirmingDisconnect = false
    /// How many queued changes the credentials just tried would orphan, while the
    /// user is being asked what to do about them.
    @State private var unsentElsewhere: Int?

    var body: some View {
        ScrollView {
            Form {
                if tracker.connection == .needsCredentials {
                    connectSection
                } else {
                    connectedSection
                }
                menuBarSection
                dockSection
                shortcutSection
                startupSection
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 460, idealWidth: 460, minHeight: 420, idealHeight: 680)
        // The user can turn the login item off in System Settings while this window
        // sits open, so re-read it whenever they come back to Scythe.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var connectSection: some View {
        Section {
            TextField("Account ID", text: $accountID)
                .textContentType(.username)
            SecureField("Personal Access Token", text: $token)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Link("Create a token…", destination: URL(string: "https://id.getharvest.com/developers")!)
                Spacer()
                Button { connect() } label: {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isConnecting ? "Connecting…" : "Connect")
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(isConnecting ? "Connecting to Harvest" : "Connect to Harvest")
                    .disabled(isConnecting || accountID.isEmpty || token.isEmpty)
            }
            .confirmationDialog(
                "Discard changes made under another account?",
                isPresented: Binding(
                    get: { unsentElsewhere != nil },
                    set: { if !$0 { unsentElsewhere = nil } }
                ),
                titleVisibility: .visible,
                presenting: unsentElsewhere
            ) { _ in
                Button("Discard and Connect", role: .destructive) { connect(discardingUnsentChanges: true) }
                Button("Cancel", role: .cancel) {}
            } message: { count in
                Text("\(count.formatted()) change\(count == 1 ? " has" : "s have") not reached Harvest yet, and \(count == 1 ? "was" : "were") made under a different account or user than this token belongs to. To send \(count == 1 ? "it" : "them"), cancel and connect with a token for that account instead.")
            }
        } header: {
            Text("Harvest")
        } footer: {
            Text("Create a personal access token at id.getharvest.com/developers. The page shows the token and the account IDs it can reach. Scythe stores the token in your Keychain and sends it only to api.harvestapp.com.")
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
        }
    }

    private var connectedSection: some View {
        Section("Harvest") {
            LabeledContent("Account", value: tracker.company?.name ?? "—")
            LabeledContent("Signed in as", value: tracker.user?.name ?? "—")
            LabeledContent("Projects", value: "\(tracker.targets.count.formatted()) task assignments")
            HStack {
                Spacer()
                Button("Disconnect…", role: .destructive) { isConfirmingDisconnect = true }
            }
            .confirmationDialog(
                "Disconnect from Harvest?",
                isPresented: $isConfirmingDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task { await tracker.disconnect() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    tracker.pendingCount > 0
                        ? "\(tracker.pendingCount.formatted()) change\(tracker.pendingCount == 1 ? "" : "s") have not reached Harvest yet and will be discarded along with the token."
                        : "The token will be removed from your Keychain. Cached entries are cleared."
                )
            }
        }
    }

    private var menuBarSection: some View {
        @Bindable var statusItemStyle = statusItemStyle
        return Section {
            Toggle("Show Scythe in the menu bar", isOn: $statusItemStyle.isVisible)
            Picker("Menu bar item", selection: $statusItemStyle.style) {
                ForEach(StatusItemStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .disabled(!statusItemStyle.isVisible)
        } header: {
            Text("Menu bar")
        } footer: {
            Text("Hide the status item without quitting Scythe. The Dock icon follows its separate setting. When visible, choose what appears beside the icon; hover it for project and task details.")
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
        }
    }

    private var dockSection: some View {
        @Bindable var dock = dock
        return Section {
            Toggle("Show Scythe in the Dock", isOn: $dock.showInDock)
            Toggle("Show minutes on the Dock icon while a timer runs", isOn: $dock.showElapsedBadge)
            Toggle(
                "Keep the Dock badge updated in the background",
                isOn: Binding(
                    get: { dock.keepBadgeUpdatedInBackground },
                    set: { enabled in
                        dock.keepBadgeUpdatedInBackground = enabled
                        if enabled { loginItem.setEnabled(true) }
                    }
                )
            )
            .disabled((!dock.showInDock || !dock.showElapsedBadge) && !dock.keepBadgeUpdatedInBackground)
        } header: {
            Text("Dock")
        } footer: {
            Text("Clicking the Dock icon opens the desktop window. With this off, Scythe lives in the menu bar and appears in the Dock only while the desktop window is open. Background updates require both Dock options above. They keep Scythe running invisibly, check only the running timer once a minute, and turn on Open Scythe at login. Quit hides Scythe while this option is on; turn it off to quit fully.")
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
        }
    }

    private var shortcutSection: some View {
        @Bindable var hotKeys = hotKeys
        return Section {
            LabeledContent("Quick entry") {
                ShortcutRecorder(shortcut: $hotKeys.shortcut)
            }
            if hotKeys.isRegistered == false {
                Label(
                    "Another app already owns \(hotKeys.shortcut.display). Pick a different combination.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            }
            if hotKeys.shortcut != .quickEntryDefault {
                HStack {
                    Spacer()
                    Button("Reset to ⌃⌥⌘T") { hotKeys.resetToDefault() }
                }
            }
        } header: {
            Text("Shortcut")
        } footer: {
            Text("Opens the quick-entry panel from any app. Scythe registers it with the window server, so no Accessibility permission is needed.")
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
        }
    }

    private var startupSection: some View {
        Section {
            Toggle(
                "Open Scythe at login",
                isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
            )
            switch loginItem.problem {
            case .needsApproval:
                Label(
                    "macOS is holding this one. Turn Scythe on under Login Items and it will stick.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                HStack {
                    Spacer()
                    Button("Open Login Items…") { loginItem.openSystemSettings() }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            case nil:
                EmptyView()
            }
        } header: {
            Text("Startup")
        } footer: {
            Text("Scythe starts without a window. Normally it runs from the menu bar; with background badge updates on, it keeps only the Dock badge path active. System Settings › General › Login Items lists it alongside everything else that starts this way.")
                .font(.caption)
                .foregroundStyle(GlassInk.secondary)
        }
    }

    private func connect(discardingUnsentChanges: Bool = false) {
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await tracker.connect(
                    HarvestCredentials(accountID: accountID, token: token),
                    discardingUnsentChanges: discardingUnsentChanges
                )
                token = ""
            } catch let error as TimeTracker.UnsentChangesBelongElsewhere {
                unsentElsewhere = error.count
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
