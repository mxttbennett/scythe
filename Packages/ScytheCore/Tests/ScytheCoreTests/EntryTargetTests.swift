import Foundation
import Testing
@testable import ScytheCore

@Suite("Changing an entry's project")
@MainActor
struct RetargetEntryTests {
    private let target = TimerTarget(
        project: Reference(id: 14308069, name: "Online Store - Phase 1"),
        task: Reference(id: 8083366, name: "Programming"),
        client: Reference(id: 5735776, name: "123 Industries")
    )

    private func account(entry: String = Fixture.timeEntry) -> RoutingTransport {
        RoutingTransport([
            RoutingTransport.Route(method: "GET", fragment: "users/me/project_assignments", body: Fixture.projectAssignmentsPage),
            RoutingTransport.Route(method: "GET", fragment: "users/me", body: Fixture.currentUser),
            RoutingTransport.Route(method: "GET", fragment: "company", body: Fixture.company),
            RoutingTransport.Route(method: "PATCH", fragment: "time_entries/", body: entry),
            RoutingTransport.Route(method: "GET", fragment: "is_running=true", body: Fixture.timeEntriesPage([])),
            RoutingTransport.Route(method: "GET", fragment: "time_entries", body: Fixture.timeEntriesPage([entry])),
        ])
    }

    private func tracker(_ transport: RoutingTransport) async -> (TimeTracker, [URL]) {
        let snapshot = URL.temporaryDirectory.appending(path: "scythe-retarget-\(UUID().uuidString).json")
        let queue = URL.temporaryDirectory.appending(path: "scythe-retarget-q-\(UUID().uuidString).json")
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

    @Test("the new project and task reach Harvest")
    func sendsProjectAndTask() async throws {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }
        let entry = try #require(tracker.entries.first)

        // Act
        await tracker.updateTarget(entry, to: target)
        await tracker.sync()

        // Assert
        let patch = try #require(await transport.calls(method: "PATCH", containing: "time_entries/636709355").first)
        #expect(patch.projectID == target.project.id)
        #expect(patch.taskID == target.task.id)
        #expect(patch.notes == nil)
        #expect(patch.hours == nil)
    }

    @Test("the entry shows its new project at once, even offline")
    func changesEntryLocally() async throws {
        // Arrange
        let transport = account()
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }
        let entry = try #require(tracker.entries.first)
        await transport.goOffline()

        // Act
        await tracker.updateTarget(entry, to: target)

        // Assert
        let changed = try #require(tracker.entries.first)
        #expect(changed.project == target.project)
        #expect(changed.task == target.task)
        #expect(changed.client == target.client)
        #expect(changed.isPending)
    }

    @Test("a locked entry keeps its project")
    func lockedEntryIsUnchanged() async throws {
        // Arrange
        let locked = Fixture.timeEntry.replacingOccurrences(of: "\"is_locked\": false", with: "\"is_locked\": true")
        let transport = account(entry: locked)
        let (tracker, files) = await tracker(transport)
        defer { cleanUp(files) }
        let entry = try #require(tracker.entries.first)

        // Act
        await tracker.updateTarget(entry, to: target)
        await tracker.sync()

        // Assert
        #expect(tracker.entries.first?.project == entry.project)
        #expect(await transport.calls(method: "PATCH", containing: "time_entries/").isEmpty)
    }

    @Test("a queued project change survives a round trip through the queue file")
    func mutationRoundTrips() throws {
        // Arrange
        let mutation = Mutation.setTarget(.server(636709355), target)

        // Act
        let decoded = try JSONDecoder().decode(Mutation.self, from: JSONEncoder().encode(mutation))

        // Assert
        #expect(decoded == mutation)
    }

    @Test("the queue sends a project change as a patch to that entry")
    func queueSendsPatch() async throws {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "scythe-queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = MutationQueue(fileURL: file)
        let transport = StubTransport([.init(body: Fixture.timeEntry)])
        let client = HarvestClient(credentials: Fixture.credentials, transport: transport, backoffScale: 0)
        await queue.enqueue(.setTarget(.server(636709355), target))

        // Act
        let report = await queue.drain(using: client)

        // Assert
        #expect(report.applied == 1)
        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path() == "/v2/time_entries/636709355")
        let body = try #require(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["project_id"] as? Int == target.project.id)
        #expect(body["task_id"] as? Int == target.task.id)
    }

    @Test("a project change on an entry still queued to be created follows its new id")
    func queueRepointsLocalEntry() async throws {
        // Arrange
        let file = URL.temporaryDirectory.appending(path: "scythe-queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = MutationQueue(fileURL: file)
        let transport = StubTransport([
            .init(status: 201, body: Fixture.runningTimeEntry),
            .init(body: Fixture.timeEntry),
        ])
        let client = HarvestClient(credentials: Fixture.credentials, transport: transport, backoffScale: 0)
        let local = UUID()
        await queue.enqueue(
            .create(local: local, target: target, spentDate: .today(), notes: nil,
                    startedAt: Date().addingTimeInterval(-1800), endedAt: Date())
        )
        await queue.enqueue(.setTarget(.local(local), target))

        // Act
        _ = await queue.drain(using: client)

        // Assert
        #expect(await transport.request(at: 1).url?.path() == "/v2/time_entries/636708906")
    }
}
