import Foundation
import Testing
@testable import ScytheCore

@Suite("Entry sort")
struct EntrySortTests {
    private static let texts = [
        "Standup", "standup", "Stand-up", "Éclair", "eclair", "Zürich", "zurich", "Task 10", "Task 9", "Task 2",
        "", "ångström", "Angstrom", "résumé", "resume", "Ｓtandup", "banana", "Banana", "10", "9", "a b", "a  b", "ab",
    ]

    private static let entries: [TrackedEntry] = (0..<400).map(makeEntry)

    private static func makeEntry(_ index: Int) -> TrackedEntry {
        let count = texts.count
        let projectName: String = texts[index % count]
        let taskName: String = texts[(index * 3) % count]
        let clientName: String = texts[(index * 5) % count]
        let notes: String = texts[(index * 7) % count]
        let date = CalendarDate(year: 2026, month: 1 + index % 12, day: 1 + (index * 11) % 28)
        return TrackedEntry(
            id: .server(Int64(index)),
            project: Reference(id: index % 7, name: projectName),
            task: Reference(id: index % 5, name: taskName),
            client: index % 4 == 0 ? nil : Reference(id: index % 3, name: clientName),
            notes: index % 6 == 0 ? nil : notes,
            spentDate: date, bankedHours: Double((index * 13) % 17) / 4, isRunning: false
        )
    }

    private func reference(_ column: EntrySortColumn, ascending: Bool) -> [Int64] {
        let order: SortOrder = ascending ? .forward : .reverse
        let sorted: [TrackedEntry]
        switch column {
        case .date: sorted = Self.entries.sorted(using: [KeyPathComparator(\TrackedEntry.spentDate, order: order)])
        case .hours: sorted = Self.entries.sorted(using: [KeyPathComparator(\TrackedEntry.bankedHours, order: order)])
        case .client: sorted = Self.entries.sorted(using: [KeyPathComparator(\TrackedEntry.clientText, order: order)])
        case .project: sorted = Self.entries.sorted(using: [KeyPathComparator(\TrackedEntry.project.name, order: order)])
        case .task: sorted = Self.entries.sorted(using: [KeyPathComparator(\TrackedEntry.task.name, order: order)])
        case .notes: sorted = Self.entries.sorted(using: [KeyPathComparator(\TrackedEntry.notesText, order: order)])
        }
        return sorted.compactMap { $0.id.serverID }
    }

    @Test("each column sorts exactly as KeyPathComparator does", arguments: EntrySortColumn.allCases, [true, false])
    func matchesKeyPathComparator(column: EntrySortColumn, ascending: Bool) {
        // Act
        let sorted = EntrySort.sorted(Self.entries, by: [EntrySortKey(column, ascending: ascending)]).compactMap { $0.id.serverID }

        // Assert
        #expect(sorted == reference(column, ascending: ascending))
    }

    @Test("a second key breaks ties in the first")
    func twoKeys() {
        // Act
        let sorted = EntrySort.sorted(Self.entries, by: [EntrySortKey(.project), EntrySortKey(.date, ascending: false)])

        // Assert
        let expected = Self.entries.sorted(using: [
            KeyPathComparator(\TrackedEntry.project.name), KeyPathComparator(\TrackedEntry.spentDate, order: .reverse),
        ])
        #expect(sorted.map(\.id) == expected.map(\.id))
    }

    @Test("entries that compare equal keep the order they arrived in")
    func stable() {
        // Arrange
        let same = (0..<50).map { index in
            TrackedEntry(
                id: .server(Int64(index)), project: Reference(id: 1, name: "Same"), task: Reference(id: 1, name: "Same"),
                spentDate: CalendarDate(year: 2026, month: 1, day: 1), bankedHours: 1, isRunning: false
            )
        }

        // Act
        let sorted = EntrySort.sorted(same, by: [EntrySortKey(.project, ascending: false)])

        // Assert
        #expect(sorted.compactMap { $0.id.serverID } == Array(0..<50).map(Int64.init))
    }

    @Test("nothing to sort, or nothing to sort by, returns the entries as they are")
    func degenerate() {
        // Act & Assert
        #expect(EntrySort.sorted([], by: [EntrySortKey(.date)]).isEmpty)
        #expect(EntrySort.sorted(Self.entries, by: []).map(\.id) == Self.entries.map(\.id))
    }
}

private extension TrackedEntry {
    var clientText: String { client?.name ?? "" }
    var notesText: String { notes ?? "" }
}
