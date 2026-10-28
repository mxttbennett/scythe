import Foundation
import Testing
@testable import ScytheCore

@Suite("Search index")
struct SearchIndexTests {
    private func entry(_ id: Int64, notes: String?, project: String = "Online Store", client: String? = "123 Industries", task: String = "Programming") -> TrackedEntry {
        TrackedEntry(
            id: .server(id),
            project: Reference(id: 1, name: project),
            task: Reference(id: 2, name: task),
            client: client.map { Reference(id: 3, name: $0) },
            notes: notes,
            spentDate: CalendarDate(year: 2026, month: 10, day: 27),
            bankedHours: 1, isRunning: false
        )
    }

    private var entries: [TrackedEntry] {
        [
            entry(1, notes: "COG-1553: Cogniform Mobile | Submissions"),
            entry(2, notes: "Café menu review", project: "Marketing Website", client: "ABC Corp", task: "Copywriting"),
            entry(3, notes: nil, project: "Meetings", client: nil, task: "Meetings"),
            entry(4, notes: "Weekly standup", project: "Cogniform Development", client: "EnterBridge Technologies"),
        ]
    }

    private func matches(_ text: String, index: SearchIndex?) -> [Int64] {
        var filter = EntryFilter()
        filter.text = text
        return filter.apply(to: entries, index: index).compactMap { $0.id.serverID }
    }

    @Test("an index finds exactly what a search without one finds")
    func sameResultsAsPlainSearch() {
        // Arrange
        let index = SearchIndex(entries)

        // Act & Assert
        for query in ["cogniform", "COGNIFORM submissions", "cafe", "café", "abc corp", "standup enterbridge", "nothing here", "   ", ""] {
            #expect(matches(query, index: index) == matches(query, index: nil), "query: \(query)")
        }
    }

    @Test("a search ignores case and accents")
    func foldsCaseAndAccents() {
        // Arrange
        let index = SearchIndex(entries)

        // Act & Assert
        #expect(matches("CAFE", index: index) == [2])
        #expect(matches("cafÉ", index: index) == [2])
    }

    @Test("each word may match a different field")
    func wordsAcrossFields() {
        // Arrange
        let index = SearchIndex(entries)

        // Act & Assert
        #expect(matches("standup cogniform", index: index) == [4])
    }

    @Test("an entry the index has not seen is still searched")
    func entryMissingFromIndex() {
        // Arrange
        let index = SearchIndex(Array(entries.prefix(2)))

        // Act & Assert
        #expect(matches("standup", index: index) == [4])
    }
}
