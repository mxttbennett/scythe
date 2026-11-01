import Foundation
import ScytheCore

struct Rng: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Two years of one heavy user's entries, generated from a fixed seed so every run measures the same work.
struct Dataset: Sendable {
    static let today = CalendarDate(year: 2026, month: 10, day: 31)
    static let now = Date(timeIntervalSince1970: 1_793_400_000)

    let entries: [TrackedEntry]
    let targets: [TimerTarget]
    let harvestPages: [Data]
    let projectIDs: [Int]

    private static let clients = ["Northwind Traders", "Café Béhar", "Zürich Labs", "Acme Health", "Globex", "Initech"]
    private static let tasks = [
        "Programming", "Project Management", "Design", "Code Review", "Meetings", "Support", "Documentation", "QA & Testing",
    ]
    private static let verbs = [
        "Reviewed", "Implemented", "Fixed", "Planned", "Refactored", "Investigated", "Paired on", "Estimated", "Deployed",
    ]
    private static let subjects = [
        "checkout flow", "café reservation form", "invoice export", "OAuth refresh bug", "ticket FF-1234",
        "release notes", "sprint planning", "résumé parser", "Zürich pilot", "analytics dashboard", "standup",
        "search relevance", "billing webhook", "onboarding emails", "permissions audit",
    ]

    static func make(entryCount: Int) -> Dataset {
        var rng = Rng(state: 0x5C17_4E)
        var projects: [(ref: Reference, client: Reference)] = []
        var targets: [TimerTarget] = []
        for index in 0..<40 {
            let client = Reference(id: 5_000 + index % clients.count, name: clients[index % clients.count])
            let project = Reference(id: 14_000_000 + index, name: "\(["Website", "Mobile app", "Platform", "Retainer", "Migration"][index % 5]) \(index / 5 + 1)")
            projects.append((project, client))
            for (taskIndex, name) in tasks.enumerated() {
                targets.append(TimerTarget(project: project, task: Reference(id: 8_000_000 + taskIndex, name: name), client: client))
            }
        }

        var entries: [TrackedEntry] = []
        var day = today
        var nextID: Int64 = 700_000_000
        var daysBack = 0
        while entries.count < entryCount, daysBack < EntryHistory.backfillDays {
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: day.startOfDay())
            let isWeekend = weekday == 1 || weekday == 7
            if !isWeekend || Int.random(in: 0..<10, using: &rng) == 0 {
                for _ in 0..<Int.random(in: 6...11, using: &rng) where entries.count < entryCount {
                    let pick = min(Int.random(in: 0..<40, using: &rng), Int.random(in: 0..<40, using: &rng))
                    let (project, client) = projects[pick]
                    let task = Reference(id: 8_000_000 + Int.random(in: 0..<tasks.count, using: &rng), name: "")
                    let taskName = tasks[task.id - 8_000_000]
                    let notes = Int.random(in: 0..<100, using: &rng) < 15 ? nil : Self.note(&rng)
                    let stamp = day.startOfDay().addingTimeInterval(Double(Int.random(in: 8 * 3600...18 * 3600, using: &rng)))
                    entries.append(TrackedEntry(
                        id: .server(nextID), project: project, task: Reference(id: task.id, name: taskName),
                        client: client, notes: notes, spentDate: day,
                        bankedHours: Double(Int.random(in: 1...16, using: &rng)) / 4,
                        isRunning: false, isBillable: Int.random(in: 0..<10, using: &rng) < 8,
                        updatedAt: stamp, createdAt: stamp
                    ))
                    nextID += 1
                }
            }
            day = day.adding(days: -1)
            daysBack += 1
        }

        return Dataset(
            entries: entries, targets: targets,
            harvestPages: pages(for: entries, perPage: 2000),
            projectIDs: projects.map(\.ref.id)
        )
    }

    private static func note(_ rng: inout Rng) -> String {
        var text = "\(verbs.randomElement(using: &rng)!) \(subjects.randomElement(using: &rng)!)"
        if Int.random(in: 0..<4, using: &rng) == 0 { text += " and \(subjects.randomElement(using: &rng)!)" }
        if Int.random(in: 0..<10, using: &rng) == 0 { text += ". Follow-up needed with the team before the next release." }
        return text
    }

    private static func pages(for entries: [TrackedEntry], perPage: Int) -> [Data] {
        let totalPages = (entries.count + perPage - 1) / perPage
        let base = "https://api.harvestapp.com/v2/time_entries?per_page=\(perPage)&user_id=1782959"
        return (0..<totalPages).map { page in
            let slice = entries[page * perPage..<min(entries.count, (page + 1) * perPage)]
            let next = page + 1 < totalPages ? "\"\(base)&page=\(page + 2)\"" : "null"
            let nextPage = page + 1 < totalPages ? String(page + 2) : "null"
            let body = slice.map(json).joined(separator: ",")
            return Data("""
            {"time_entries":[\(body)],"per_page":\(perPage),"total_pages":\(totalPages),"total_entries":\(entries.count),\
            "next_page":\(nextPage),"previous_page":null,"page":\(page + 1),\
            "links":{"first":"\(base)&page=1","next":\(next),"previous":null,"last":"\(base)&page=\(totalPages)"}}
            """.utf8)
        }
    }

    private static func json(_ entry: TrackedEntry) -> String {
        let stamp = entry.createdAt?.formatted(.iso8601) ?? ""
        let notes = entry.notes.map { "\"\($0)\"" } ?? "null"
        let client = entry.client!
        let id = entry.id.serverID!
        return """
        {"id":\(id),"spent_date":"\(entry.spentDate)","hours":\(entry.bankedHours),"hours_without_timer":\(entry.bankedHours),\
        "rounded_hours":\(entry.bankedHours),"notes":\(notes),"is_locked":false,"locked_reason":null,"is_closed":false,\
        "is_billed":false,"timer_started_at":null,"started_time":null,"ended_time":null,"is_running":false,\
        "billable":\(entry.isBillable),"budgeted":true,"billable_rate":150.0,"cost_rate":null,\
        "created_at":"\(stamp)","updated_at":"\(stamp)","user":{"id":1782959,"name":"Kim Allen"},\
        "client":{"id":\(client.id),"name":"\(client.name)","currency":"USD"},\
        "project":{"id":\(entry.project.id),"name":"\(entry.project.name)","code":"PRJ"},\
        "task":{"id":\(entry.task.id),"name":"\(entry.task.name)"},\
        "user_assignment":{"id":125068554,"is_project_manager":true,"is_active":true,"use_default_rates":true,\
        "budget":null,"created_at":"\(stamp)","updated_at":"\(stamp)","hourly_rate":100.0},\
        "task_assignment":{"id":155505014,"billable":true,"is_active":true,"created_at":"\(stamp)",\
        "updated_at":"\(stamp)","hourly_rate":100.0,"budget":null},"invoice":null,"external_reference":null}
        """
    }
}

struct PagedTransport: HarvestTransport {
    let pages: [Data]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (pages[page - 1], response)
    }
}
