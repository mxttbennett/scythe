import Testing
@testable import Scythe

@Suite("Choice search")
struct ChoiceSearchTests {
    @Test("matches every query word without case or accent sensitivity")
    func matchesWords() {
        // Arrange
        let available = ["Café Support", "Café Development", "Client Work"]

        // Act
        let results = ChoiceSearch.filter(available, query: "CAFE supp", searchText: { $0 })

        // Assert
        #expect(results == ["Café Support"])
    }

    @Test("blank queries keep available choices in their original order")
    func blankQueryPreservesChoices() {
        // Arrange
        let available = ["Support", "Programming", "Café Redesign"]

        // Act
        let results = ChoiceSearch.filter(available, query: "  \t", searchText: { $0 })

        // Assert
        #expect(results == available)
    }

    @Test("every query word must match the same available choice")
    func requiresEveryQueryWord() {
        // Arrange
        let available = ["Client Support", "Project Management", "Support"]

        // Act
        let results = ChoiceSearch.filter(available, query: "project support", searchText: { $0 })

        // Assert
        #expect(results.isEmpty)
    }
}
