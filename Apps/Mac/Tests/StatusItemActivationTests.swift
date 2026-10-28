import AppKit
import Testing
@testable import Scythe

@Suite("Status item activation")
@MainActor
struct StatusItemActivationTests {
    private let panel = NSPanel(
        contentRect: NSRect(x: -30_000, y: -30_000, width: 100, height: 100),
        styleMask: [.borderless],
        backing: .buffered,
        defer: true
    )

    private func window(shown: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -30_000, y: -30_000, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        if shown { window.orderFrontRegardless() }
        return window
    }

    @Test("with no other window open the panel activates the app")
    func activatesWithNoOtherWindow() {
        // Act & Assert
        #expect(StatusItemController.shouldActivate(over: [panel], excluding: panel))
    }

    @Test("an open desktop window keeps the app inactive so it is not raised")
    func skipsActivationOverVisibleWindow() {
        // Arrange
        let desktop = window(shown: true)
        defer { desktop.orderOut(nil) }

        // Act & Assert
        #expect(!StatusItemController.shouldActivate(over: [panel, desktop], excluding: panel))
    }

    @Test("a closed window does not hold activation back")
    func activatesWithHiddenWindow() {
        // Act & Assert
        #expect(StatusItemController.shouldActivate(over: [panel, window(shown: false)], excluding: panel))
    }

    @Test("another panel, such as quick entry, does not hold activation back")
    func activatesWithAnotherPanelOpen() {
        // Arrange
        let other = NSPanel(
            contentRect: NSRect(x: -30_000, y: -30_000, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        other.orderFrontRegardless()
        defer { other.orderOut(nil) }

        // Act & Assert
        #expect(StatusItemController.shouldActivate(over: [panel, other], excluding: panel))
    }
}
