import Foundation
import Testing
@testable import ScytheCore

@Suite("Searching targets")
struct TargetSearchTests {
    private func target(_ project: Int, _ projectName: String, _ task: Int, _ taskName: String, client: String?) -> TimerTarget {
        TimerTarget(
            project: Reference(id: project, name: projectName),
            task: Reference(id: task, name: taskName),
            client: client.map { Reference(id: 900 + project, name: $0) }
        )
    }

    private var targets: [TimerTarget] {
        [
            target(1, "Cogniform Development", 10, "Software Development", client: "EnterBridge Technologies"),
            target(2, "Platform Build", 20, "DEPL - Post-Deployment Support", client: "FBCCA"),
            target(2, "Platform Build", 21, "Client Work - Detailed in Note", client: "FBCCA"),
            target(3, "Support", 21, "Client Work - Detailed in Note", client: "FBCCA"),
            target(4, "Meetings", 40, "Meetings - enter details in notes", client: "EnterBridge Technologies"),
            target(5, "Café Redesign", 50, "Design", client: nil),
        ]
    }

    private func found(_ query: String) -> [String] {
        targets.matching(query).map { "\($0.project.name) / \($0.task.name)" }
    }

    @Test("a blank query keeps every target in its ranked order")
    func blankQueryKeepsEverything() {
        // Arrange
        let blanks = ["", " ", "  \t "]

        // Act & Assert
        for blank in blanks {
            #expect(targets.matching(blank) == targets, "query: \(blank.debugDescription)")
        }
    }

    @Test("finds a target by its client, its project or its task")
    func matchesEachField() {
        // Act & Assert
        #expect(found("enterbridge") == ["Cogniform Development / Software Development", "Meetings / Meetings - enter details in notes"])
        #expect(found("cogniform") == ["Cogniform Development / Software Development"])
        #expect(found("post-deployment") == ["Platform Build / DEPL - Post-Deployment Support"])
    }

    @Test("ignores case and accents")
    func foldsCaseAndAccents() {
        // Act & Assert
        #expect(found("CAFE") == ["Café Redesign / Design"])
        #expect(found("cafÉ") == ["Café Redesign / Design"])
        #expect(found("COGNIFORM development") == ["Cogniform Development / Software Development"])
    }

    @Test("matches part of a word")
    func matchesPartialWords() {
        // Act & Assert
        #expect(found("softw") == ["Cogniform Development / Software Development"])
        #expect(found("rbridge") == ["Cogniform Development / Software Development", "Meetings / Meetings - enter details in notes"])
    }

    @Test("needs every word, in any order, and each may come from a different field")
    func needsEveryWord() {
        // Act & Assert
        #expect(found("fbcca support") == ["Platform Build / DEPL - Post-Deployment Support", "Support / Client Work - Detailed in Note"])
        #expect(found("support fbcca") == found("fbcca support"))
        #expect(found("fbcca meetings").isEmpty)
        #expect(found("enterbridge software") == ["Cogniform Development / Software Development"])
    }

    @Test("a word cannot straddle two fields")
    func wordsStayWithinAField() {
        // Act & Assert
        #expect(found("technologiescogniform").isEmpty)
        #expect(found("developmentsoftware").isEmpty)
    }

    @Test("returns nothing when no target matches")
    func noMatch() {
        // Act & Assert
        #expect(found("zzz").isEmpty)
    }

    @Test("keeps the order the targets arrived in")
    func keepsRankedOrder() {
        // Arrange
        let reversed = Array(targets.reversed())

        // Act
        let matched = reversed.matching("client")

        // Assert
        #expect(matched.map(\.project.name) == ["Support", "Platform Build"])
    }

    @Test("grouping what matched offers a project only the tasks that matched")
    func groupingKeepsTheMatchingTask() {
        // Act
        let grouped = targets.matching("detailed").groupedByProject()

        // Assert
        #expect(grouped.map(\.project.name) == ["Platform Build", "Support"])
        #expect(grouped.map { $0.tasks.map(\.name) } == [["Client Work - Detailed in Note"], ["Client Work - Detailed in Note"]])
    }

    @Test("a project matched by name keeps all its tasks")
    func projectNameKeepsAllTasks() {
        // Act
        let grouped = targets.matching("platform").groupedByProject()

        // Assert
        #expect(grouped.count == 1)
        #expect(grouped[0].tasks.map(\.name) == ["DEPL - Post-Deployment Support", "Client Work - Detailed in Note"])
    }
}
