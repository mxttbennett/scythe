import Foundation

extension TimeTracker {
    /// What the desktop window's history cache reads, which the tracker does not keep.
    public var historyFetcher: HistoryFetcher {
        HistoryFetcher { [weak self] from, to, updatedSince in
            guard let self else { return [] }
            return try await self.fetchHistory(from: from, to: to, updatedSince: updatedSince).map { TrackedEntry($0) }
        }
    }

    public func historyUserID() async throws -> Int {
        try await currentUser().id
    }

    private func fetchHistory(from: CalendarDate, to: CalendarDate?, updatedSince: Date?) async throws -> [TimeEntry] {
        let user = try await currentUser()
        return try await client.timeEntries(userID: user.id, from: from, to: to, updatedSince: updatedSince)
    }

    /// With hours, logs them on that day; without, starts a timer now.
    public func addEntry(
        against target: TimerTarget,
        on date: CalendarDate,
        hours: Double?,
        notes: String?
    ) async {
        if let hours {
            await logHours(hours, against: target, on: date, notes: notes)
        } else {
            await start(target, notes: notes)
        }
    }

    /// Logs finished time on any day; it appears once the queue has sent it and the next sync reads it back.
    public func logHours(
        _ hours: Double,
        against target: TimerTarget,
        on date: CalendarDate,
        notes: String? = nil
    ) async {
        guard hours > 0 else { return }
        let started = date.startOfDay()
        noteRecent(target)
        await enqueue([
            .create(
                local: UUID(), target: target, spentDate: date, notes: notes,
                startedAt: started, endedAt: started.addingTimeInterval(hours * 3600)
            )
        ])
    }
}
