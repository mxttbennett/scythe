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

    @Test("folding plain ASCII gives what Foundation's folding gives", arguments: [
        "Weekly Standup", "COG-1553: Cogniform Mobile | Submissions", "  spaced   out ", "", "123 Industries", "a_b-c.d/e",
    ])
    func asciiFoldMatchesFoundation(text: String) {
        // Act
        let folded = SearchIndex.fold(text)

        // Assert
        #expect(folded == text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    @Test("a search finds the same entries Foundation's range search finds, however the text is composed")
    func agreesWithFoundationSearch() {
        // Arrange
        let composed = "Caf\u{E9} r\u{E9}sum\u{E9} \u{C5}ngstr\u{F6}m Z\u{FC}rich"
        let decomposed = "Cafe\u{301} re\u{301}sume\u{301} A\u{30A}ngstro\u{308}m Zu\u{308}rich"
        let candidates = [
            entry(1, notes: composed), entry(2, notes: decomposed), entry(3, notes: "plain notes"),
            entry(4, notes: "한글 메모"), entry(5, notes: "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF} 메모"),
        ]
        let index = SearchIndex(candidates)

        for query in ["cafe", "CAFÉ", "Cafe\u{301}", "resume", "angstrom", "ångström", "zurich", "Zürich", "한글", "메모", "plain", "nope"] {
            // Act
            var filter = EntryFilter()
            filter.text = query
            let found = filter.apply(to: candidates, index: index).compactMap { $0.id.serverID }
            let unindexed = filter.apply(to: candidates).compactMap { $0.id.serverID }

            // Assert
            let expected = candidates.filter { candidate in
                let haystack = [candidate.notes, candidate.project.name, candidate.client?.name, candidate.task.name]
                    .compactMap { $0 }.joined(separator: " ")
                return query.split(whereSeparator: \.isWhitespace).allSatisfy {
                    haystack.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            }.compactMap { $0.id.serverID }
            #expect(found == expected, "indexed: \(query)")
            #expect(unindexed == expected, "unindexed: \(query)")
        }
    }

    @Test("a word longer than the text matches nothing, and an empty entry never crashes")
    func shortHaystack() {
        // Arrange
        let blank = TrackedEntry(
            id: .server(9), project: Reference(id: 1, name: ""), task: Reference(id: 2, name: ""),
            spentDate: CalendarDate(year: 2026, month: 10, day: 27), bankedHours: 0, isRunning: false
        )
        var filter = EntryFilter()
        filter.text = "anything"

        // Act & Assert
        #expect(filter.apply(to: [blank], index: SearchIndex([blank])).isEmpty)
        #expect(filter.apply(to: [blank]).isEmpty)
    }
}
