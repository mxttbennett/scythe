import Foundation
import Testing
@testable import SheavesCore

@Suite("Saved queries")
struct SavedQueryTests {
    private func store() -> SavedQueryStore {
        SavedQueryStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "queries-\(UUID().uuidString).json"))
    }

    @Test("a store with no file has no queries")
    func emptyByDefault() {
        // Act & Assert
        #expect(store().load().isEmpty)
    }

    @Test("queries come back as saved, filter included")
    func roundTrip() throws {
        // Arrange
        let store = store()
        let query = SavedQuery(
            name: "Unbilled this month",
            filter: EntryFilter(period: .preset(.thisMonth), billable: true)
        )

        // Act
        try store.save([query])
        let loaded = store.load()

        // Assert
        #expect(loaded == [query])
    }
}
