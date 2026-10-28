import Foundation
import Testing
@testable import ScytheCore

@Suite("Entry created time")
struct CreatedTimeTests {
    private let createdAt = Date(timeIntervalSince1970: 1_793_112_060)

    private func entry(createdAt: Date?) -> TrackedEntry {
        TrackedEntry(
            id: .server(1),
            project: Reference(id: 1, name: "Online Store"),
            task: Reference(id: 2, name: "Programming"),
            spentDate: CalendarDate(year: 2026, month: 10, day: 27),
            bankedHours: 1, isRunning: false, createdAt: createdAt
        )
    }

    @Test("the created time survives a round trip through JSON")
    func roundTrips() throws {
        // Act
        let decoded = try JSONDecoder().decode(TrackedEntry.self, from: JSONEncoder().encode(entry(createdAt: createdAt)))

        // Assert
        #expect(decoded.createdAt == createdAt)
    }

    @Test("an entry saved before it carried a created time still loads, without one")
    func legacyEntryLoads() throws {
        // Arrange
        let data = try JSONEncoder().encode(entry(createdAt: createdAt))
        var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["createdAt"] = nil

        // Act
        let decoded = try JSONDecoder().decode(TrackedEntry.self, from: JSONSerialization.data(withJSONObject: fields))

        // Assert
        #expect(decoded.createdAt == nil)
    }

    @Test("an entry made here is stamped with the time it was made")
    func localEntryIsStamped() throws {
        // Arrange
        let before = Date()

        // Act
        let made = TrackedEntry(
            id: .local(UUID()),
            project: Reference(id: 1, name: "Online Store"),
            task: Reference(id: 2, name: "Programming"),
            spentDate: .today(), bankedHours: 0, isRunning: true
        )

        // Assert
        let stamp = try #require(made.createdAt)
        #expect(stamp >= before && stamp <= Date())
    }
}
