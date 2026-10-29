import Foundation
import ScytheCore

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
    var isAddingEntry = false
    var isSidebarVisible: Bool {
        didSet { defaults.set(isSidebarVisible, forKey: Self.sidebarVisibilityDefaultsKey) }
    }
    var filter: EntryFilter {
        didSet { persistFilter() }
    }
    private(set) var savedQueries: [SavedQuery]

    private let store: SavedQueryStore?
    @ObservationIgnored private let defaults: UserDefaults

    private static let filterDefaultsKey = "explorerFilter"
    private static let sidebarVisibilityDefaultsKey = "desktopSidebarVisible"

    init(store: SavedQueryStore? = SavedQueryStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        isSidebarVisible = defaults.object(forKey: Self.sidebarVisibilityDefaultsKey) as? Bool ?? true
        filter = defaults.data(forKey: Self.filterDefaultsKey)
            .flatMap { try? JSONDecoder().decode(EntryFilter.self, from: $0) } ?? EntryFilter()
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

    private func persistFilter() {
        guard let data = try? JSONEncoder().encode(filter) else { return }
        defaults.set(data, forKey: Self.filterDefaultsKey)
    }
}
