import AppKit
import ScytheCore
import SwiftUI
import Testing
@testable import Scythe

@Suite("Entry row")
@MainActor
struct EntryRowTests {
    @Test("a selected row paints the selection background")
    func selectedRowPaintsBackground() async throws {
        // Arrange
        let tracker = await makeTracker()
        let entry = try #require(tracker.entries.first { !$0.isRunning })

        // Act
        let selected = try await render(row(entry, isSelected: true, tracker: tracker))
        let plain = try await render(row(entry, isSelected: false, tracker: tracker))

        // Assert
        #expect(try #require(selected.colorAt(x: selected.pixelsWide / 2, y: 1)).alphaComponent > 0.99)
        #expect(try #require(plain.colorAt(x: plain.pixelsWide / 2, y: 1)).alphaComponent == 0)
    }

    @Test("a selected row draws its icons and status marks in light ink")
    func selectedRowHasNoDarkMarks() async throws {
        // Arrange
        let tracker = await makeTracker()
        var entry = try #require(tracker.entries.first { $0.permalink != nil })
        entry.isLocked = true
        entry.isPending = true

        // Act
        let selected = try await render(row(entry, isSelected: true, tracker: tracker))
        let plain = try await render(row(entry, isSelected: false, tracker: tracker))

        // Assert
        #expect(darkPixels(in: selected) == 0)
        #expect(darkPixels(in: plain) > 0)
    }

    @Test("a field opened on a selected row shows dark text on its light fill")
    func fieldOnSelectedRowIsReadable() async throws {
        // Arrange
        let tracker = await makeTracker()
        let entry = try #require(tracker.entries.first { !$0.isRunning })

        // Act
        let editing = try await render(row(entry, isSelected: true, isEditing: true, tracker: tracker))

        // Assert
        #expect(darkPixels(in: editing) > 0)
    }

    @Test("clicking a row in the panel selects it")
    func clickSelectsRow() async throws {
        // Arrange
        let tracker = await makeTracker()
        let hosting = NSHostingView(rootView: DayView().environment(tracker))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: hosting.frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        let before = try snapshot(of: hosting)

        // Act
        // Click down the title column until the frame changes; a non-key window selects in grey, not blue.
        var changed = 0
        var y: CGFloat = 50
        while changed < 1_500, y < hosting.bounds.height - 60 {
            try await click(window, at: NSPoint(x: 100, y: hosting.bounds.height - y))
            changed = try differingPixels(before, snapshot(of: hosting))
            y += 6
        }

        // Assert
        #expect(changed >= 1_500)
    }

    private func click(_ window: NSWindow, at point: NSPoint) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(60))
    }

    private func snapshot(of view: NSView) throws -> [UInt8] {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.bitmapData)
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    private func differingPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).reduce(0) { $1.0 == $1.1 ? $0 : $0 + 1 } / 4
    }

    private func row(
        _ entry: TrackedEntry,
        isSelected: Bool,
        isEditing: Bool = false,
        tracker: TimeTracker
    ) -> some View {
        EntryRow(
            entry: entry,
            format: HoursFormat(company: tracker.company),
            isSelected: isSelected,
            isEditingNotes: .constant(isEditing),
            isEditingHours: .constant(isEditing),
            isConfirmingResume: .constant(false),
            isConfirmingDelete: .constant(false)
        )
        .environment(tracker)
        .frame(width: 380)
    }

    /// Hosted in a window that is never shown, because a field only fills in once its view appears.
    private func render(_ view: some View) async throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// Near-black and opaque: the corners outside a rounded row are transparent black and must not count.
    private func darkPixels(in rep: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                if color.redComponent < 0.3, color.greenComponent < 0.3, color.blueComponent < 0.3 { count += 1 }
            }
        }
        return count
    }

    private func makeTracker() async -> TimeTracker {
        let scratch = URL.temporaryDirectory.appending(path: "scythe-row-\(UUID().uuidString)")
        let tracker = TimeTracker(
            client: HarvestClient(credentials: .init(accountID: "0", token: "none"), transport: DemoAccount()),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.row-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: scratch.appending(path: "snapshot.json")),
            queue: MutationQueue(fileURL: scratch.appending(path: "queue.json"))
        )
        await tracker.sync()
        return tracker
    }
}
