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

    @Test("a client and project too long for one line stack instead of truncating")
    func longClientAndProjectStack() async throws {
        // Arrange
        let tracker = await makeTracker()
        var short = try #require(tracker.entries.first { $0.client != nil && !$0.isRunning })
        short.notes = nil
        var long = short
        long.client = Reference(id: 1, name: "EnterBridge Technologies International")
        long.project = Reference(id: 2, name: "Cogniform Development and Maintenance")

        // Act
        let shortHeight = try await render(row(short, isSelected: false, tracker: tracker)).pixelsHigh
        let longHeight = try await render(row(long, isSelected: false, tracker: tracker)).pixelsHigh

        // Assert
        #expect(longHeight > shortHeight)
    }

    @Test("notes keep their explicit line breaks")
    func notesKeepLineBreaks() async throws {
        // Arrange
        let tracker = await makeTracker()
        var entry = try #require(tracker.entries.first { !$0.isRunning })
        entry.notes = "First line\nSecond line\nThird line"
        var flattened = entry
        flattened.notes = "First line Second line Third line"

        // Act
        let multilineHeight = try await render(row(entry, isSelected: false, tracker: tracker)).pixelsHigh
        let singleLineHeight = try await render(row(flattened, isSelected: false, tracker: tracker)).pixelsHigh

        // Assert
        #expect(multilineHeight > singleLineHeight)
    }

    @Test("double-clicking a row and clicking Edit invoke the editor action")
    func editActionsOpenEditor() async throws {
        // Arrange
        let tracker = await makeTracker()
        let entry = try #require(tracker.entries.first)
        var editCount = 0
        let hosting = NSHostingView(rootView: row(
            entry,
            isSelected: false,
            tracker: tracker,
            onEdit: { editCount += 1 }
        ))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))

        // Act
        try await click(window, at: NSPoint(x: 100, y: hosting.bounds.height / 2))
        try await click(window, at: NSPoint(x: 100, y: hosting.bounds.height / 2))

        // Assert
        #expect(editCount == 1)

        // Act
        try await click(window, at: NSPoint(x: 336, y: 19))

        // Assert
        #expect(editCount == 2)
    }

    @Test("a client and project that fit share one line")
    func shortClientAndProjectShareALine() async throws {
        // Arrange
        let tracker = await makeTracker()
        var withClient = try #require(tracker.entries.first { $0.client != nil && !$0.isRunning })
        withClient.notes = nil
        var withoutClient = withClient
        withoutClient.client = nil

        // Act
        let withHeight = try await render(row(withClient, isSelected: false, tracker: tracker)).pixelsHigh
        let withoutHeight = try await render(row(withoutClient, isSelected: false, tracker: tracker)).pixelsHigh

        // Assert
        #expect(withHeight == withoutHeight)
    }

    @Test("clicking a row in the panel selects it")
    func clickSelectsRow() async throws {
        // Arrange
        let tracker = await makeTracker()
        let history = HistoryModel(tracker: tracker, store: nil, fetcher: DemoHistory.fetcher, userID: 1)
        let hosting = NSHostingView(rootView: DayView().environment(tracker).environment(history))
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

    @Test("space and S toggle the selected entry")
    func keyboardTogglesSelectedEntry() async throws {
        // Arrange
        let transport = CountingDemoAccount()
        let tracker = await makeTracker(transport: transport)
        #expect(!tracker.entries.isEmpty)
        let history = HistoryModel(tracker: tracker, store: nil, fetcher: DemoHistory.fetcher, userID: 1)
        let hosting = NSHostingView(rootView: DayView().environment(tracker).environment(history))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))

        // Act
        sendKey(125, characters: "\u{F701}", to: window)
        sendKey(49, characters: " ", to: window)
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        #expect(await transport.stopCount() == 1)

        // Act — a held Space sends repeat key-downs, which must not restart the timer.
        sendKey(49, characters: " ", isARepeat: true, to: window)
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        #expect(await transport.restartCount() == 0)
        #expect(await transport.stopCount() == 1)

        // Act
        sendKey(1, characters: "s", to: window)
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        #expect(await transport.stopCount() == 2)
    }

    @Test("E opens the selected entry editor")
    func eOpensSelectedEntryEditor() async throws {
        // Arrange
        let tracker = await makeTracker()
        let history = HistoryModel(tracker: tracker, store: nil, fetcher: DemoHistory.fetcher, userID: 1)
        let hosting = NSHostingView(rootView: DayView().environment(tracker).environment(history))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))

        // Act
        sendKey(125, characters: "\u{F701}", to: window)
        sendKey(14, characters: "e", to: window)
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        #expect(window.attachedSheet != nil)
    }

    @Test("Return opens the selected entry editor and Command-Return saves it")
    func returnEditsAndCommandReturnSavesSelectedEntry() async throws {
        // Arrange
        let tracker = await makeTracker()
        let history = HistoryModel(tracker: tracker, store: nil, fetcher: DemoHistory.fetcher, userID: 1)
        let hosting = NSHostingView(rootView: DayView().environment(tracker).environment(history))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))

        // Act
        sendKey(125, characters: "\u{F701}", to: window)
        sendKey(36, characters: "\r", to: window)
        try await Task.sleep(for: .milliseconds(200))
        #expect(window.attachedSheet != nil)
        sendKey(36, characters: "\r", modifiers: .command, to: window)
        try await Task.sleep(for: .milliseconds(300))

        // Assert
        #expect(window.attachedSheet == nil)
    }

    @Test("space starts a selected stopped entry")
    func spaceStartsStoppedEntry() async throws {
        // Arrange
        let transport = CountingDemoAccount()
        let tracker = await makeTracker(transport: transport)
        let stopped = try #require(tracker.entries.first { !$0.isRunning })
        let rowIndex = try #require(tracker.entries.firstIndex { $0.id == stopped.id })
        let history = HistoryModel(tracker: tracker, store: nil, fetcher: DemoHistory.fetcher, userID: 1)
        let hosting = NSHostingView(rootView: DayView().environment(tracker).environment(history))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))

        // Act
        for _ in 0...rowIndex {
            sendKey(125, characters: "\u{F701}", to: window)
        }
        sendKey(49, characters: " ", to: window)
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        #expect(await transport.restartCount() == 1)
    }

    private func sendKey(
        _ keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false,
        to window: NSWindow
    ) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        )!
        window.sendEvent(event)
    }

    private func click(_ window: NSWindow, at point: NSPoint) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
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
        tracker: TimeTracker,
        onEdit: @escaping () -> Void = {}
    ) -> some View {
        EntryRow(
            entry: entry,
            format: HoursFormat(company: tracker.company),
            isSelected: isSelected,
            onEdit: onEdit,
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

    private func makeTracker(transport: any HarvestTransport = DemoAccount()) async -> TimeTracker {
        let scratch = URL.temporaryDirectory.appending(path: "scythe-row-\(UUID().uuidString)")
        let tracker = TimeTracker(
            client: HarvestClient(credentials: .init(accountID: "0", token: "none"), transport: transport),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.row-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: scratch.appending(path: "snapshot.json")),
            queue: MutationQueue(fileURL: scratch.appending(path: "queue.json"))
        )
        await tracker.sync()
        return tracker
    }
}

private actor CountingDemoAccount: HarvestTransport {
    private let demo = DemoAccount()
    private var stops = 0
    private var restarts = 0

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path.hasSuffix("/stop") == true { stops += 1 }
        if request.url?.path.hasSuffix("/restart") == true { restarts += 1 }
        return try await demo.send(request)
    }

    func stopCount() -> Int { stops }
    func restartCount() -> Int { restarts }
}
