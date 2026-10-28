import AppKit
import ScytheCore
import Testing
@testable import Scythe

@Suite("Status item menu")
@MainActor
struct StatusItemMenuTests {
    private func entry(running: Bool) -> TrackedEntry {
        TrackedEntry(
            id: .server(1), project: Reference(id: 1, name: "Online Store"),
            task: Reference(id: 2, name: "Programming"), spentDate: .today(),
            bankedHours: 0.5, isRunning: running,
            timerStartedAt: running ? Date() : nil
        )
    }

    private func titles(of menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    @Test("with nothing tracked there is one Open item, then Settings and Quit")
    func idleMenu() {
        // Act
        let menu = StatusItemController.menu(for: .idle, target: NSObject())

        // Assert
        #expect(titles(of: menu) == ["Open Scythe", "Settings…", "-", "Quit Scythe"])
    }

    @Test("Open Scythe opens the desktop window")
    func openOpensTheDesktopWindow() throws {
        // Arrange
        let target = NSObject()

        // Act
        let menu = StatusItemController.menu(for: .idle, target: target)

        // Assert
        let open = try #require(menu.items.first)
        #expect(NSStringFromSelector(try #require(open.action)) == "openDesktopItem")
        #expect(open.target === target)
    }

    @Test("a running timer offers to pause it first")
    func runningMenuLeadsWithPause() {
        // Act
        let menu = StatusItemController.menu(for: .running(entry(running: true)), target: NSObject())

        // Assert
        #expect(titles(of: menu) == ["Pause Programming", "-", "Open Scythe", "Settings…", "-", "Quit Scythe"])
    }

    @Test("a paused entry offers to resume it first")
    func pausedMenuLeadsWithResume() {
        // Act
        let menu = StatusItemController.menu(for: .recent(entry(running: false)), target: NSObject())

        // Assert
        #expect(titles(of: menu) == ["Resume Programming", "-", "Open Scythe", "Settings…", "-", "Quit Scythe"])
    }
}
