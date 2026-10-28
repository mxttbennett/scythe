import AppKit
import Foundation
import Testing
@testable import Scythe

@Suite("Status item style")
@MainActor
struct StatusItemStyleTests {
    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "StatusItemStyleTests-\(UUID().uuidString)")!
    }

    @Test("icon only draws no title")
    func iconOnlyHasNoTitle() {
        // Act
        let title = StatusItemStyle.iconOnly.title(project: "Online Store", hours: "1:30", total: "3:45")

        // Assert
        #expect(title == "")
    }

    @Test("time shows only the elapsed time")
    func timeOmitsProject() {
        // Act
        let title = StatusItemStyle.time.title(project: "Online Store", hours: "1:30", total: "3:45")

        // Assert
        #expect(title == " 1:30")
    }

    @Test("project and time keeps a short project name whole")
    func projectAndTimeKeepsShortName() {
        // Act
        let title = StatusItemStyle.projectAndTime.title(project: "Online Store", hours: "1:30", total: "3:45")

        // Assert
        #expect(title == " Online Store  1:30")
    }

    @Test("project and time shortens a long project name")
    func projectAndTimeShortensLongName() {
        // Act
        let title = StatusItemStyle.projectAndTime.title(project: "Online Store - Phase 1", hours: "1:30", total: "3:45")

        // Assert
        #expect(title == " Online Store - Ph…  1:30")
    }

    @Test("stacked puts the entry time over the day total")
    func stackedPutsTimeOverTotal() {
        // Act
        let title = StatusItemStyle.stacked.title(project: "Online Store", hours: "0:44", total: "3:45")

        // Assert
        #expect(title == "0:44\n3:45")
    }

    @Test("every style has a distinct label for the settings picker")
    func labelsAreDistinct() {
        // Act
        let labels = StatusItemStyle.allCases.map(\.label)

        // Assert
        #expect(Set(labels).count == StatusItemStyle.allCases.count)
        #expect(StatusItemStyle.stacked.label == "Icon, entry time over day total")
    }

    @Test("stacked draws two lines at menu bar height on today")
    func stackedTitleHasTwoLines() throws {
        // Act
        let title = StatusItemTitle.attributed(
            style: .stacked, project: "Online Store", hours: "0:44", total: "3:45", isToday: true
        )

        // Assert
        let paragraph = try #require(title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(title.string == "0:44\n3:45")
        #expect(paragraph.maximumLineHeight == 10)
    }

    @Test("stacked falls back to the time alone when the panel shows another day")
    func stackedTitleDropsTotalOnAnotherDay() {
        // Act
        let title = StatusItemTitle.attributed(
            style: .stacked, project: "Online Store", hours: "0:44", total: "3:45", isToday: false
        )

        // Assert
        #expect(title.string == " 0:44")
    }

    @Test("a fresh install uses the compact style")
    func defaultsToTime() {
        // Act & Assert
        #expect(StatusItemStylePreference(defaults: scratchDefaults()).style == .time)
    }

    @Test("the chosen style survives a relaunch")
    func persistsAcrossLaunches() {
        // Arrange
        let defaults = scratchDefaults()
        let preference = StatusItemStylePreference(defaults: defaults)

        // Act
        preference.style = .projectAndTime

        // Assert
        #expect(StatusItemStylePreference(defaults: defaults).style == .projectAndTime)
    }

    @Test("an unrecognised stored style falls back to the default")
    func ignoresUnknownStoredValue() {
        // Arrange
        let defaults = scratchDefaults()
        defaults.set("enormous", forKey: "statusItemStyle")

        // Act & Assert
        #expect(StatusItemStylePreference(defaults: defaults).style == .time)
    }
}
