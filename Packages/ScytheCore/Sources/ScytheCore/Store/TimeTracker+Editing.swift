extension TimeTracker {
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
