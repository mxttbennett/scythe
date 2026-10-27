import Foundation
import SheavesCore

enum DesktopSection: Hashable {
    case explorer
    case analytics
    case timesheet
}

/// What the desktop window is showing: which view, and the filter the explorer and the
/// analytics share, so a query built in one can be read as charts in the other.
@MainActor
@Observable
final class DesktopState {
    var section: DesktopSection = .explorer
    var filter = EntryFilter()
    private(set) var savedQueries: [SavedQuery]

    private let store: SavedQueryStore?

    init(store: SavedQueryStore? = SavedQueryStore()) {
        self.store = store
        savedQueries = store?.load() ?? []
    }

    func saveCurrentFilter(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedQueries.append(SavedQuery(name: trimmed, filter: filter))
        persist()
    }

    func open(_ query: SavedQuery) {
        filter = query.filter
        section = .explorer
    }

    func delete(_ query: SavedQuery) {
        savedQueries.removeAll { $0.id == query.id }
        persist()
    }

    private func persist() {
        try? store?.save(savedQueries)
    }
}
