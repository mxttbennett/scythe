import Foundation
import Testing
@testable import Sheaves

@Suite("UI scale")
@MainActor
struct UIScaleTests {
    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "UIScaleTests-\(UUID().uuidString)")!
    }

    @Test("a fresh install runs at full size")
    func defaultsToOne() {
        // Act & Assert
        #expect(UIScalePreference(defaults: scratchDefaults()).scale == 1)
    }

    @Test("zooming in moves to the next step")
    func zoomInStepsUp() {
        // Arrange
        let preference = UIScalePreference(defaults: scratchDefaults())

        // Act
        preference.zoomIn()

        // Assert
        #expect(preference.scale == 1.1)
    }

    @Test("zooming out moves to the previous step")
    func zoomOutStepsDown() {
        // Arrange
        let preference = UIScalePreference(defaults: scratchDefaults())

        // Act
        preference.zoomOut()

        // Assert
        #expect(preference.scale == 0.9)
    }

    @Test("zooming in stops at the largest step")
    func zoomInStopsAtMaximum() {
        // Arrange
        let preference = UIScalePreference(defaults: scratchDefaults())

        // Act
        for _ in 0..<20 { preference.zoomIn() }

        // Assert
        #expect(preference.scale == UIScalePreference.steps.last)
    }

    @Test("zooming out stops at the smallest step")
    func zoomOutStopsAtMinimum() {
        // Arrange
        let preference = UIScalePreference(defaults: scratchDefaults())

        // Act
        for _ in 0..<20 { preference.zoomOut() }

        // Assert
        #expect(preference.scale == UIScalePreference.steps.first)
    }

    @Test("reset returns to full size")
    func resetReturnsToOne() {
        // Arrange
        let preference = UIScalePreference(defaults: scratchDefaults())
        preference.zoomIn()
        preference.zoomIn()

        // Act
        preference.reset()

        // Assert
        #expect(preference.scale == 1)
    }

    @Test("the chosen scale survives a relaunch")
    func persistsAcrossLaunches() {
        // Arrange
        let defaults = scratchDefaults()
        let preference = UIScalePreference(defaults: defaults)

        // Act
        preference.zoomIn()

        // Assert
        #expect(UIScalePreference(defaults: defaults).scale == 1.1)
    }

    @Test("there are several steps between full size and 1.5")
    func hasFineSteps() {
        // Act
        let between = UIScalePreference.steps.filter { $0 > 1 && $0 <= 1.5 }

        // Assert
        #expect(between.count >= 4)
    }

    @Test("a stored value that is not a step falls back to full size")
    func ignoresUnknownStoredValue() {
        // Arrange
        let defaults = scratchDefaults()
        defaults.set(37.0, forKey: "uiScale")

        // Act & Assert
        #expect(UIScalePreference(defaults: defaults).scale == 1)
    }
}
