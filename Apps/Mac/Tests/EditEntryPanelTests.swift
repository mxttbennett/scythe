import AppKit
import ScytheCore
import Testing
@testable import Scythe

@Suite("Edit entry panel")
@MainActor
struct EditEntryPanelTests {
    @Test("the editor gets a full-width panel instead of the clipped menu-bar width")
    func editorHasRoomForForm() async throws {
        let tracker = await makeTracker()
        let history = HistoryModel(tracker: tracker, store: nil)
        let entry = try #require(tracker.entries.first { !$0.isRunning })
        let controller = EditEntryPanelController(tracker: tracker, history: history, uiScale: UIScalePreference())
        defer { controller.dismiss() }

        controller.present(entry)
        await Task.yield()

        let panel = try #require(controller.window)
        #expect(panel.frame.width >= 520)

        controller.dismissIfClickingOutside(at: NSPoint(x: panel.frame.midX, y: panel.frame.midY))
        #expect(controller.window === panel)

        controller.dismissIfClickingOutside(at: NSPoint(x: panel.frame.maxX + 1, y: panel.frame.midY))
        #expect(controller.window == nil)
        #expect(!panel.isVisible)
    }

    private func makeTracker() async -> TimeTracker {
        let scratch = URL.temporaryDirectory.appending(path: "scythe-edit-panel-\(UUID().uuidString)")
        let tracker = TimeTracker(
            client: HarvestClient(credentials: .init(accountID: "0", token: "none"), transport: DemoAccount()),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.edit-panel-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: scratch.appending(path: "snapshot.json")),
            queue: MutationQueue(fileURL: scratch.appending(path: "queue.json"))
        )
        await tracker.sync()
        return tracker
    }
}
