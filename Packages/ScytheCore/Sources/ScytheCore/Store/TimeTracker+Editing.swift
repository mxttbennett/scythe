import Foundation

extension TimeTracker {
    public func currentEntry(matching id: TrackedEntry.ID) async -> TrackedEntry? {
        let resolvedID = await queue.resolvedID(for: id)
        return entries.first { $0.id == resolvedID }
    }

    /// Applies a sheet's changes against the entry's current identity and timer state,
    /// then persists the complete edit as one queued batch.
    public func updateEntry(
        _ entry: TrackedEntry,
        notes: String?,
        hours: Double?,
        target: TimerTarget?,
        spentDate: CalendarDate? = nil
    ) async {
        guard !entry.isLocked else { return }
        let id = await queue.resolvedID(for: entry.id)
        guard let current = entries.first(where: { $0.id == id }), !current.isLocked else { return }

        let hoursAsOf = Date()
        mutateLocally(id) {
            if let notes { $0.notes = notes }
            if let target {
                $0.project = target.project
                $0.task = target.task
                $0.client = target.client
            }
            if let spentDate { $0.spentDate = spentDate }
            if let hours {
                $0.bankedHours = hours
                if current.isRunning {
                    $0.isRunning = true
                    $0.timerStartedAt = hoursAsOf
                } else {
                    $0.isRunning = false
                    $0.timerStartedAt = nil
                }
            }
            $0.isPending = true
        }

        var mutations: [Mutation] = []
        if current.isRunning, let hours {
            if let notes { mutations.append(.update(id, notes: notes, hours: nil)) }
            mutations.append(.adjust(id, hours: hours, asOf: hoursAsOf))
            noteLastActivity()
            restartClock()
        } else if notes != nil || hours != nil {
            mutations.append(.update(id, notes: notes, hours: hours))
        }
        if let target { mutations.append(.setTarget(id, target)) }
        if let spentDate, spentDate != current.spentDate { mutations.append(.setDate(id, spentDate)) }
        if !mutations.isEmpty { await enqueue(mutations) }
    }

    public func updateTarget(_ entry: TrackedEntry, to target: TimerTarget) async {
        guard !entry.isLocked else { return }
        mutateLocally(entry.id) {
            $0.project = target.project
            $0.task = target.task
            $0.client = target.client
            $0.isPending = true
        }
        await enqueue([.setTarget(entry.id, target)])
    }
}
