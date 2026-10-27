import ScytheCore
import Testing
@testable import Scythe

@Suite("Panel selection")
@MainActor
struct DayViewSelectionTests {
    private let first = TrackedEntry.ID.server(1)
    private let second = TrackedEntry.ID.server(2)
    private let third = TrackedEntry.ID.server(3)

    private var ids: [TrackedEntry.ID] { [first, second, third] }

    @Test("down with nothing selected lands on the first entry")
    func downFromNothing() {
        // Act
        let next = DayView.selection(after: nil, moving: 1, in: ids)

        // Assert
        #expect(next == first)
    }

    @Test("up with nothing selected lands on the first entry")
    func upFromNothing() {
        // Act
        let next = DayView.selection(after: nil, moving: -1, in: ids)

        // Assert
        #expect(next == first)
    }

    @Test("down moves to the next entry")
    func downMoves() {
        // Act
        let next = DayView.selection(after: first, moving: 1, in: ids)

        // Assert
        #expect(next == second)
    }

    @Test("up moves to the previous entry")
    func upMoves() {
        // Act
        let next = DayView.selection(after: third, moving: -1, in: ids)

        // Assert
        #expect(next == second)
    }

    @Test("down stops at the last entry")
    func downStopsAtEnd() {
        // Act
        let next = DayView.selection(after: third, moving: 1, in: ids)

        // Assert
        #expect(next == third)
    }

    @Test("up stops at the first entry")
    func upStopsAtStart() {
        // Act
        let next = DayView.selection(after: first, moving: -1, in: ids)

        // Assert
        #expect(next == first)
    }

    @Test("a selection that left the day counts as nothing selected")
    func goneSelectionStartsOver() {
        // Act
        let next = DayView.selection(after: .server(99), moving: 1, in: ids)

        // Assert
        #expect(next == first)
    }

    @Test("an empty day selects nothing")
    func emptyDay() {
        // Act
        let next = DayView.selection(after: nil, moving: 1, in: [])

        // Assert
        #expect(next == nil)
    }
}
