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

    /// Logs finished time against any day, which is how a timesheet cell with nothing in
    /// it takes a number. The entry shows up once the queue has sent it and the next sync
    /// has read it back.
    public func logHours(_ hours: Double, against target: TimerTarget, on date: CalendarDate) async {
        guard hours > 0 else { return }
        let started = date.startOfDay()
        noteRecent(target)
        await enqueue([
            .create(
                local: UUID(), target: target, spentDate: date, notes: nil,
                startedAt: started, endedAt: started.addingTimeInterval(hours * 3600)
            )
        ])
    }
}
