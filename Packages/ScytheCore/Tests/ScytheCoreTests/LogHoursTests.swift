import Foundation
import Testing
@testable import ScytheCore

@Suite("Logging hours by hand")
@MainActor
struct LogHoursTests {
    private let target = TimerTarget(
        project: Reference(id: 14308069, name: "Online Store - Phase 1"),
        task: Reference(id: 8083366, name: "Programming"),
        client: Reference(id: 5735776, name: "123 Industries")
    )
    private let day = CalendarDate(year: 2026, month: 8, day: 20)

    private func account() -> RoutingTransport {
        let none = Fixture.timeEntriesPage([])
        return RoutingTransport([
            RoutingTransport.Route(method: "GET", fragment: "users/me/project_assignments", body: Fixture.projectAssignmentsPage),
            RoutingTransport.Route(method: "GET", fragment: "users/me", body: Fixture.currentUser),
            RoutingTransport.Route(method: "GET", fragment: "company", body: Fixture.company),
            RoutingTransport.Route(method: "POST", fragment: "time_entries", body: Fixture.timeEntry, status: 201),
            RoutingTransport.Route(method: "GET", fragment: "is_running=true", body: none),
            RoutingTransport.Route(method: "GET", fragment: "time_entries", body: none),
        ])
    }

    private func tracker(_ transport: RoutingTransport) async -> (TimeTracker, [URL]) {
        let snapshot = URL.temporaryDirectory.appending(path: "scythe-log-\(UUID().uuidString).json")
        let queue = URL.temporaryDirectory.appending(path: "scythe-log-q-\(UUID().uuidString).json")
        let tracker = TimeTracker(
            client: HarvestClient(credentials: Fixture.credentials, transport: transport, backoffScale: 0),
            keychain: KeychainStore(service: "com.mxttbennett.scythe.tests-\(UUID().uuidString)"),
            snapshots: SnapshotStore(fileURL: snapshot),
            queue: MutationQueue(fileURL: queue)
        )
        await tracker.sync()
        return (tracker, [snapshot, queue])
    }

    private func cleanUp(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    @Test("logged hours reach Harvest as that many hours on that day")
    func sendsHoursOnTheChosenDay() async throws {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }

        // Act
        await tracker.logHours(1.5, against: target, on: day)
        await tracker.sync()

        // Assert
        let created = try #require(await transport.calls(method: "POST", containing: "time_entries").first)
        #expect(created.hours == 1.5)
        #expect(created.spentDate == day.description)
        #expect(created.projectID == target.project.id)
    }

    @Test("notes travel with the entry")
    func sendsNotes() async throws {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }

        // Act
        await tracker.logHours(2, against: target, on: day, notes: "COG-1553: review")
        await tracker.sync()

        // Assert
        let created = try #require(await transport.calls(method: "POST", containing: "time_entries").first)
        #expect(created.notes == "COG-1553: review")
    }

    @Test("an entry without notes sends none")
    func omitsMissingNotes() async throws {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }

        // Act
        await tracker.logHours(1, against: target, on: day)
        await tracker.sync()

        // Assert
        let created = try #require(await transport.calls(method: "POST", containing: "time_entries").first)
        #expect(created.notes == nil)
    }

    @Test("adding an entry with hours logs them on the chosen day")
    func addEntryWithHoursLogs() async throws {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }

        // Act
        await tracker.addEntry(against: target, on: day, hours: 1.25, notes: "Review")
        await tracker.sync()

        // Assert
        let created = try #require(await transport.calls(method: "POST", containing: "time_entries").first)
        #expect(created.hours == 1.25)
        #expect(created.spentDate == day.description)
        #expect(created.notes == "Review")
    }

    @Test("adding an entry without hours starts a timer on the project")
    func addEntryWithoutHoursStartsTimer() async throws {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }

        // Act
        await tracker.addEntry(against: target, on: .today(), hours: nil, notes: "Standup")
        await tracker.sync()

        // Assert
        let created = try #require(await transport.calls(method: "POST", containing: "time_entries").first)
        #expect(created.projectID == target.project.id)
        #expect(created.notes == "Standup")
        #expect(created.spentDate == CalendarDate.today().description)
    }

    @Test("zero or negative hours send nothing")
    func ignoresNonPositiveHours() async {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }

        // Act
        await tracker.logHours(0, against: target, on: day)
        await tracker.logHours(-1, against: target, on: day)
        await tracker.sync()

        // Assert
        #expect(await transport.calls(method: "POST", containing: "time_entries").isEmpty)
    }
}
