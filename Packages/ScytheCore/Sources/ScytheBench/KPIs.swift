import Foundation
import ScytheCore

/// One frame at 120 Hz. Work on the main thread past this drops a frame.
private let frame = 8.0
/// Past this a person notices waiting, wherever the work runs.
private let instant = 100.0

enum KPIs {
    static func all(_ data: Dataset) -> [KPI] {
        startup(data) + sync(data) + explorer(data) + analytics(data) + timesheet(data) + dates(data) + targets(data)
    }

    private static func warmHistory(_ data: Dataset) async throws -> EntryHistory {
        var history = EntryHistory()
        try await history.refresh(userID: 1, using: HistoryFetcher { _, _, _ in data.entries }, today: Dataset.today, now: Dataset.now)
        return history
    }

    private static func startup(_ data: Dataset) -> [KPI] {
        let file = URL.temporaryDirectory.appending(path: "scythe-bench-history-\(ProcessInfo.processInfo.processIdentifier).json")
        return [
            KPI(id: "startup.history-load", group: "Startup", title: "Read history.json from disk and decode it", thread: .background, budgetMs: instant) {
                let store = HistoryStore(fileURL: file)
                try store.save(try await warmHistory(data))
                return { consume(store.load()) }
            },
            KPI(id: "startup.history-save", group: "Startup", title: "Encode and write history.json after an edit", thread: .background, budgetMs: instant) {
                let store = HistoryStore(fileURL: file)
                let history = try await warmHistory(data)
                return { try store.save(history) }
            },
        ]
    }

    private static func sync(_ data: Dataset) -> [KPI] {
        [
            KPI(id: "sync.harvest-decode", group: "Sync", title: "Fetch and decode a full two-year backfill", thread: .background, budgetMs: instant * 2) {
                let client = HarvestClient(
                    credentials: HarvestCredentials(accountID: "1", token: "t"), transport: PagedTransport(pages: data.harvestPages)
                )
                return { consume(try await client.timeEntries(userID: 1, from: Dataset.today.adding(days: -730), to: nil, updatedSince: nil)) }
            },
            KPI(id: "sync.history-cold-merge", group: "Sync", title: "Merge a full backfill into an empty history", thread: .background, budgetMs: instant) {
                return { consume(try await warmHistory(data)) }
            },
            KPI(id: "sync.history-refresh", group: "Sync", title: "Incremental refresh: 15 edits plus the 60-day window", thread: .background, budgetMs: instant) {
                let box = Box(try await warmHistory(data))
                let recent = data.entries.filter { $0.spentDate >= Dataset.today.adding(days: -EntryHistory.reconcileDays) }
                let changed = Array(data.entries.prefix(15))
                let fetcher = HistoryFetcher { _, _, since in since == nil ? recent : changed }
                return { try await box.value.refresh(userID: 1, using: fetcher, today: Dataset.today, now: Dataset.now) }
            },
            KPI(id: "sync.history-absorb", group: "Sync", title: "Fold the menu bar's day back into the history", thread: .main, budgetMs: frame) {
                let box = Box(try await warmHistory(data))
                let day = data.entries[0].spentDate
                let live = data.entries.filter { $0.spentDate == day }
                return { box.value.absorb(live, on: day) }
            },
        ]
    }

    private static func explorer(_ data: Dataset) -> [KPI] {
        [
            KPI(id: "explorer.index-build", group: "Explorer", title: "Build the search index after any change", thread: .background, budgetMs: instant) {
                return { consume(SearchIndex(data.entries)) }
            },
            KPI(id: "explorer.search-text", group: "Explorer", title: "Filter by text with the search index", thread: .background, budgetMs: frame) {
                let index = SearchIndex(data.entries)
                let filter = EntryFilter(text: "review café")
                return { consume(filter.apply(to: data.entries, today: Dataset.today, weekStart: .monday, index: index)) }
            },
            KPI(id: "explorer.filter-facets", group: "Explorer", title: "Filter by period, three projects and billable", thread: .background, budgetMs: frame) {
                let filter = EntryFilter(period: .preset(.last90Days), projectIDs: Set(data.projectIDs.prefix(3)), billable: true)
                return { consume(filter.apply(to: data.entries, today: Dataset.today, weekStart: .monday)) }
            },
            KPI(id: "explorer.facets", group: "Explorer", title: "Rebuild the filter menus after any change", thread: .main, budgetMs: frame) {
                return { consume(HistoryFacets(data.entries)) }
            },
            KPI(id: "explorer.sort-text-column", group: "Explorer", title: "Sort the table by a text column", thread: .background, budgetMs: frame) {
                let keys = [EntrySortKey(.project)]
                return { consume(EntrySort.sorted(data.entries, by: keys)) }
            },
            KPI(id: "explorer.sort-date-column", group: "Explorer", title: "Sort the table by date, newest first", thread: .background, budgetMs: frame) {
                let keys = [EntrySortKey(.date, ascending: false)]
                return { consume(EntrySort.sorted(data.entries, by: keys)) }
            },
            KPI(id: "explorer.csv-export", group: "Explorer", title: "Export every entry as CSV", thread: .main, budgetMs: instant) {
                return { consume(CSVExport.entries(data.entries, asOf: Dataset.now)) }
            },
        ]
    }

    private static func analytics(_ data: Dataset) -> [KPI] {
        @Sendable func render(_ entries: [TrackedEntry]) {
            let analytics = EntryAnalytics(entries, asOf: Dataset.now)
            consume((
                analytics.totalHours, analytics.billableHours, analytics.billableShare, analytics.nonBillableHours,
                analytics.activeDays, analytics.averagePerActiveDay,
                analytics.weekdayActiveDays, analytics.weekendActiveDays,
                analytics.averagePerActiveWeekday, analytics.averagePerActiveWeekendDay
            ))
            consume((analytics.byProject(), analytics.byClient(), analytics.byTask()))
            consume((analytics.byDay(), analytics.byWeek(weekStart: .monday), analytics.byMonth()))
        }
        return [
            KPI(id: "analytics.open-all", group: "Analytics", title: "Draw the Analytics tab over every entry", thread: .main, budgetMs: frame) {
                return { render(EntryFilter().apply(to: data.entries, today: Dataset.today, weekStart: .monday)) }
            },
            KPI(id: "analytics.open-filtered", group: "Analytics", title: "Redraw Analytics after typing a search", thread: .main, budgetMs: frame) {
                let filter = EntryFilter(period: .preset(.thisYear), text: "review")
                return { render(filter.apply(to: data.entries, today: Dataset.today, weekStart: .monday)) }
            },
        ]
    }

    private static func timesheet(_ data: Dataset) -> [KPI] {
        let week = data.entries[0].spentDate.startOfWeek(weekStart: .monday)
        return [
            KPI(id: "timesheet.build-week", group: "Timesheet", title: "Build a week's timesheet from the history", thread: .main, budgetMs: frame) {
                return { consume(Timesheet.build(from: data.entries, weekStart: week, asOf: Dataset.now)) }
            },
        ]
    }

    private static func dates(_ data: Dataset) -> [KPI] {
        [
            KPI(id: "dates.presets", group: "Dates", title: "Resolve all ten period presets", thread: .main, budgetMs: frame) {
                return { for preset in DatePreset.allCases { consume(preset.range(today: Dataset.today, weekStart: .monday)) } }
            },
            KPI(id: "dates.arithmetic", group: "Dates", title: "Add days to a date and measure the gap (per 1,000)", thread: .main, budgetMs: frame) {
                return {
                    for offset in 0..<1000 {
                        let shifted = Dataset.today.adding(days: -offset)
                        consume(shifted.daysSince(Dataset.today))
                    }
                }
            },
        ]
    }

    private static func targets(_ data: Dataset) -> [KPI] {
        [
            KPI(id: "targets.search", group: "Targets", title: "Filter the project picker as you type", thread: .main, budgetMs: frame) {
                return { consume(data.targets.matching("web des")) }
            },
            KPI(id: "targets.group", group: "Targets", title: "Group picker rows by project", thread: .main, budgetMs: frame) {
                return { consume(data.targets.groupedByProject()) }
            },
        ]
    }
}
