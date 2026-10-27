import Foundation

public struct SavedQuery: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var filter: EntryFilter

    public init(id: UUID = UUID(), name: String, filter: EntryFilter) {
        self.id = id
        self.name = name
        self.filter = filter
    }
}

public struct SavedQueryStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(appName: String = "Sheaves") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let directory = base.appending(path: appName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appending(path: "saved-queries.json")
    }

    public func load() -> [SavedQuery] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SavedQuery].self, from: data)) ?? []
    }

    public func save(_ queries: [SavedQuery]) throws {
        try JSONEncoder().encode(queries).write(to: fileURL, options: .atomic)
    }
}
