import Foundation
import Testing
@testable import Scythe

@Suite("Note links")
struct NoteLinksTests {
    private func links(in notes: String) -> [URL] {
        NoteLinks.attributed(notes).runs.compactMap(\.link)
    }

    @Test("a URL in a note becomes a link")
    func linksAUrl() {
        // Act
        let found = links(in: "Review https://example.com/pull/12 today")

        // Assert
        #expect(found == [URL(string: "https://example.com/pull/12")!])
    }

    @Test("the text around a link is untouched")
    func keepsTheText() {
        // Arrange
        let notes = "Review https://example.com/pull/12 today"

        // Act
        let attributed = NoteLinks.attributed(notes)

        // Assert
        #expect(String(attributed.characters) == notes)
    }

    @Test("punctuation that ends a sentence is not part of the link")
    func dropsTrailingPunctuation() {
        // Act
        let found = links(in: "Fixed in https://example.com/pull/9.")

        // Assert
        #expect(found == [URL(string: "https://example.com/pull/9")!])
    }

    @Test("every URL in a note is linked")
    func linksEachUrl() {
        // Act
        let found = links(in: "https://example.com/a and http://example.org/b")

        // Assert
        #expect(found.count == 2)
    }

    @Test("file names and bare domains are not links")
    func ignoresBareNames() {
        // Act
        let found = links(in: "Update README.md and example.com")

        // Assert
        #expect(found.isEmpty)
    }

    @Test("a ticket id alone is not a link")
    func ignoresTicketIds() {
        // Act
        let found = links(in: "COG-1553: Cogniform Mobile | Submissions")

        // Assert
        #expect(found.isEmpty)
    }
}
