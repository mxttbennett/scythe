import AppKit
import Foundation
import Testing
@testable import Scythe

@Suite("Dock preference")
@MainActor
struct DockPreferenceTests {
    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DockPreferenceTests-\(UUID().uuidString)")!
    }

    @Test("a fresh install shows Scythe in the Dock")
    func defaultsToShowing() {
        // Act & Assert
        #expect(DockPreference(defaults: scratchDefaults()).showInDock)
    }

    @Test("turning the Dock icon off survives a relaunch")
    func persistsOff() {
        // Arrange
        let defaults = scratchDefaults()
        let preference = DockPreference(defaults: defaults)

        // Act
        preference.showInDock = false

        // Assert
        #expect(!DockPreference(defaults: defaults).showInDock)
    }

    @Test("turning it back on survives a relaunch")
    func persistsOn() {
        // Arrange
        let defaults = scratchDefaults()
        let preference = DockPreference(defaults: defaults)
        preference.showInDock = false

        // Act
        preference.showInDock = true

        // Assert
        #expect(DockPreference(defaults: defaults).showInDock)
    }

    @Test("a change is announced so the activation policy can follow")
    func announcesChange() {
        // Arrange
        let preference = DockPreference(defaults: scratchDefaults())
        var announced = 0
        preference.onChange = { announced += 1 }

        // Act
        preference.showInDock = false

        // Assert
        #expect(announced == 1)
    }

    @Test("setting the value it already has announces nothing")
    func ignoresRepeatedValue() {
        // Arrange
        let preference = DockPreference(defaults: scratchDefaults())
        var announced = 0
        preference.onChange = { announced += 1 }

        // Act
        preference.showInDock = true

        // Assert
        #expect(announced == 0)
    }

    @Test("with the icon on, the app is a regular one even with no window")
    func regularWhenShowing() {
        // Arrange
        let preference = DockPreference(defaults: scratchDefaults())

        // Act & Assert
        #expect(preference.activationPolicy == .regular)
    }

    @Test("with the icon off and no window, the app is an accessory")
    func accessoryWhenHidden() {
        // Arrange
        let preference = DockPreference(defaults: scratchDefaults())
        preference.showInDock = false

        // Act & Assert
        #expect(preference.activationPolicy == .accessory)
    }

    @Test("with the icon off, an open desktop window still makes the app a regular one")
    func regularWhileWindowIsOpen() {
        // Arrange
        let preference = DockPreference(defaults: scratchDefaults())
        preference.showInDock = false

        // Act
        preference.isDesktopWindowOpen = true

        // Assert
        #expect(preference.activationPolicy == .regular)
    }

    @Test("closing the desktop window with the icon off goes back to an accessory")
    func accessoryAfterWindowCloses() {
        // Arrange
        let preference = DockPreference(defaults: scratchDefaults())
        preference.showInDock = false
        preference.isDesktopWindowOpen = true

        // Act
        preference.isDesktopWindowOpen = false

        // Assert
        #expect(preference.activationPolicy == .accessory)
    }
}
