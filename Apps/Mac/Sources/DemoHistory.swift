#if DEBUG
import Foundation
import ScytheCore

/// Sixteen weeks of made-up entries for the demo account, so the desktop window has
/// something to chart. Seeded, so every launch draws the same weeks.
enum DemoHistory {
    private struct Work {
        var client: Reference?
        var project: Reference
        var tasks: [Reference]
        var billable: Bool
        var notes: [String]
    }

    private static let work: [Work] = [
        Work(
            client: Reference(id: 1, name: "123 Industries"),
            project: Reference(id: 101, name: "Online Store - Phase 1"),
            tasks: [Reference(id: 201, name: "Programming"), Reference(id: 202, name: "Design Review"), Reference(id: 203, name: "Project Management")],
            billable: true,
            notes: ["ONL-%d: Checkout flow", "ONL-%d: Cart totals rounding", "ONL-%d: Address validation https://example.com/pull/%d", "Sprint planning"]
        ),
        Work(
            client: Reference(id: 2, name: "ABC Corp"),
            project: Reference(id: 102, name: "Marketing Website"),
            tasks: [Reference(id: 204, name: "Graphic Design"), Reference(id: 205, name: "Copywriting")],
            billable: true,
            notes: ["MKT-%d: Landing page hero", "MKT-%d: Pricing table", "Brand refresh review"]
        ),
        Work(
            client: Reference(id: 1, name: "123 Industries"),
            project: Reference(id: 103, name: "Internal Tools"),
            tasks: [Reference(id: 201, name: "Programming")],
            billable: false,
            notes: ["Deploy script cleanup", "Dashboard queries", "Dependency updates"]
        ),
        Work(
            client: Reference(id: 3, name: "Northwind"),
            project: Reference(id: 104, name: "Mobile App"),
            tasks: [Reference(id: 201, name: "Programming"), Reference(id: 206, name: "QA")],
            billable: true,
            notes: ["APP-%d: Offline sync", "APP-%d: Push notification copy", "Regression pass https://example.com/qa/%d"]
        ),
        Work(
            client: nil,
            project: Reference(id: 105, name: "Meetings"),
            tasks: [Reference(id: 207, name: "Meetings")],
            billable: false,
            notes: ["Weekly standup", "All hands", "1:1"]
        ),
    ]

    static var fetcher: HistoryFetcher {
        HistoryFetcher { from, to, _ in
            let today = CalendarDate.today()
            return generate(upTo: today).filter { $0.spentDate >= from && $0.spentDate <= (to ?? today) }
        }
    }

    private static func generate(upTo today: CalendarDate) -> [TrackedEntry] {
        var seed: UInt64 = 0x5EAF
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }

        let hourChoices: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]
        var entries: [TrackedEntry] = []
        var id: Int64 = 800_000_000

        for offset in stride(from: 111, through: 0, by: -1) {
            let date = today.adding(days: -offset)
            let weekday = Calendar.current.component(.weekday, from: date.startOfDay())
            guard weekday != 1, weekday != 7 else { continue }

            for _ in 0..<(3 + next(3)) {
                let job = work[next(work.count)]
                let task = job.tasks[next(job.tasks.count)]
                let template = job.notes[next(job.notes.count)]
                let ticket = 100 + next(900)
                let notes = template.contains("%d")
                    ? template.replacingOccurrences(of: "%d", with: String(ticket))
                    : template
                let permalink = notes.range(of: #"^[A-Z]+-[0-9]+"#, options: .regularExpression)
                    .flatMap { URL(string: "https://linear.app/demo/issue/\(notes[$0])") }
                id += 1
                entries.append(
                    TrackedEntry(
                        id: .server(id), project: job.project, task: task, client: job.client,
                        notes: notes, permalink: permalink, spentDate: date, bankedHours: hourChoices[next(hourChoices.count)],
                        isRunning: false, isLocked: offset > 60, isBillable: job.billable,
                        updatedAt: date.startOfDay()
                    )
                )
            }
        }
        return entries
    }
}
#endif
