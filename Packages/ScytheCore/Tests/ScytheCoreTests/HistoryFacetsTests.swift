import Foundation
import Testing
@testable import ScytheCore

@Suite("History facets")
struct HistoryFacetsTests {
    private func entry(
        _ id: Int64, project: (Int, String), task: (Int, String), client: (Int, String)?
    ) -> TrackedEntry {
        TrackedEntry(
            id: .server(id),
            project: Reference(id: project.0, name: project.1),
            task: Reference(id: task.0, name: task.1),
            client: client.map { Reference(id: $0.0, name: $0.1) },
            spentDate: CalendarDate(year: 2026, month: 10, day: 27), bankedHours: 1, isRunning: false
        )
    }

    private var entries: [TrackedEntry] {
        [
            entry(1, project: (10, "Website"), task: (20, "Design"), client: (30, "Acme")),
            entry(2, project: (10, "Website"), task: (21, "Programming"), client: (30, "Acme")),
            entry(3, project: (11, "Zebra app"), task: (20, "Design"), client: (31, "Globex")),
            entry(4, project: (12, "Internal"), task: (22, "Meetings"), client: nil),
            entry(5, project: (10, "Website (renamed)"), task: (20, "Design (renamed)"), client: (30, "Acme (renamed)")),
            entry(6, project: (11, "Zebra app"), task: (22, "Meetings"), client: (31, "Globex")),
        ]
    }

    @Test("lists each project, client and task once, in name order, keeping the first name seen")
    func distinctSorted() {
        // Act
        let facets = HistoryFacets(entries)

        // Assert
        #expect(facets.projects.map(\.name) == ["Internal", "Website", "Zebra app"])
        #expect(facets.clients.map(\.name) == ["Acme", "Globex"])
        #expect(facets.tasks.map(\.name) == ["Design", "Meetings", "Programming"])
        #expect(facets.projectsByID[10]?.name == "Website")
    }

    @Test("records which projects and tasks appear with each client, and tasks with each project")
    func relationships() {
        // Act
        let facets = HistoryFacets(entries)

        // Assert
        #expect(facets.projectIDsByClient == [30: [10], 31: [11]])
        #expect(facets.taskIDsByClient == [30: [20, 21], 31: [20, 22]])
        #expect(facets.taskIDsByProject == [10: [20, 21], 11: [20, 22], 12: [22]])
        #expect(facets.allProjectIDs == [10, 11, 12])
        #expect(facets.allTaskIDs == [20, 21, 22])
    }

    @Test("an empty history has nothing to offer")
    func empty() {
        // Act
        let facets = HistoryFacets([])

        // Assert
        #expect(facets.projects.isEmpty && facets.clients.isEmpty && facets.tasks.isEmpty)
        #expect(facets.allProjectIDs.isEmpty && facets.allTaskIDs.isEmpty)
    }
}
