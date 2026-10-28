import SwiftUI
import Testing
@testable import Scythe

@Suite("Hashed colour")
struct HashedColorTests {
    @Test("the hash matches the published FNV-1a values")
    func knownHashes() {
        // Act & Assert
        #expect(HashedColor.fnv1a("") == 0xcbf29ce484222325)
        #expect(HashedColor.fnv1a("a") == 0xaf63dc4c8601ec8c)
    }

    @Test("a name gets the same colour every time")
    func stable() {
        // Act & Assert
        #expect(HashedColor.components(for: "FBCCA", kind: .client) == HashedColor.components(for: "FBCCA", kind: .client))
    }

    @Test("a client, a project and a task with the same name do not share a colour")
    func kindIsPartOfTheKey() {
        // Arrange
        let client = HashedColor.components(for: "Support", kind: .client)
        let project = HashedColor.components(for: "Support", kind: .project)
        let task = HashedColor.components(for: "Support", kind: .task)

        // Act & Assert
        #expect(client != project)
        #expect(project != task)
        #expect(client != task)
    }

    @Test("every colour is a valid hue in one of four tiers")
    func componentsAreInRange() {
        // Arrange
        let names = (0..<500).map { "name \($0)" }

        // Act
        let all = names.map { HashedColor.components(for: $0, kind: .project) }

        // Assert
        #expect(all.allSatisfy { (0..<1).contains($0.hue) })
        #expect(Set(all.map { "\($0.saturation)/\($0.brightness)" }).count == 4)
    }

    @Test("names spread across the colours rather than clumping")
    func spread() {
        // Arrange
        let names = (0..<200).map { "project \($0)" }

        // Act
        let distinct = Set(names.map { HashedColor.components(for: $0, kind: .project) })

        // Assert
        #expect(distinct.count >= 90)
    }

    @Test("the SwiftUI colour is built from the same components")
    func colourMatchesComponents() {
        // Arrange
        let c = HashedColor.components(for: "FBCCA", kind: .client)

        // Act & Assert
        #expect(HashedColor.color(for: "FBCCA", kind: .client) == Color(hue: c.hue, saturation: c.saturation, brightness: c.brightness))
        #expect(HashedColor.color(for: "FBCCA", kind: .client) != HashedColor.color(for: "FBCCA", kind: .project))
    }

    @Test("a blank name still has a colour")
    func blankName() {
        // Act & Assert
        #expect((0..<1).contains(HashedColor.components(for: "", kind: .client).hue))
    }
}
