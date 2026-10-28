import AppKit
import ScytheCore

enum DockBadge {
    /// Rounds to the nearest minute as the entry list does, so the badge and the row never disagree.
    static func label(for activity: TimeTracker.Activity, at now: Date, enabled: Bool) -> String? {
        guard enabled, case .running(let entry) = activity else { return nil }
        return Int((entry.hours(asOf: now) * 60).rounded()).formatted()
    }
}

/// Keeps the Dock icon's badge in step with the running timer.
@MainActor
final class DockBadgeController {
    private let tracker: TimeTracker
    private let preference: DockPreference
    private let show: @MainActor (String?) -> Void
    private var shown: String?

    init(
        tracker: TimeTracker,
        preference: DockPreference,
        show: @escaping @MainActor (String?) -> Void = { NSApp.dockTile.badgeLabel = $0 }
    ) {
        self.tracker = tracker
        self.preference = preference
        self.show = show
        observe()
    }

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            // onChange fires before the value is applied, so re-read on the next turn.
            Task { @MainActor in self?.observe() }
        }
    }

    /// The tracker ticks every second while a timer runs; the Dock is only told when the text changes.
    private func refresh() {
        let label = DockBadge.label(for: tracker.activity, at: tracker.now, enabled: preference.showElapsedBadge)
        guard label != shown else { return }
        shown = label
        show(label)
    }
}
