import ScytheCore
import Testing
@testable import Scythe

@Suite("Timesheet row targets")
@MainActor
struct TimesheetTargetTests {
    @Test("candidates keep their ranked order and omit duplicates and existing rows")
    func orderedUniqueTargets() {
        // Arrange
        let first = TimerTarget(project: Reference(id: 1, name: "First"), task: Reference(id: 11, name: "Build"))
        let duplicate = TimerTarget(project: Reference(id: 1, name: "First"), task: Reference(id: 11, name: "Build"))
        let second = TimerTarget(project: Reference(id: 2, name: "Second"), task: Reference(id: 22, name: "Plan"))

        // Act
        let result = TimesheetView.orderedUniqueTargets([first, duplicate, second], excluding: [second.id])

        // Assert
        #expect(result == [first])
    }
}
