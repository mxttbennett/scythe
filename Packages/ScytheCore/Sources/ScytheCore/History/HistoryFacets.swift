import Foundation

/// What the Explorer's filter menus offer, derived from the entries: every project, client and
/// task that appears, and which of them appear together.
public struct HistoryFacets: Sendable {
    public private(set) var projects: [Reference] = []
    public private(set) var clients: [Reference] = []
    public private(set) var tasks: [Reference] = []
    public private(set) var projectIDsByClient: [Int: Set<Int>] = [:]
    public private(set) var taskIDsByClient: [Int: Set<Int>] = [:]
    public private(set) var taskIDsByProject: [Int: Set<Int>] = [:]
    public private(set) var projectsByID: [Int: Reference] = [:]
    public private(set) var tasksByID: [Int: Reference] = [:]
    public private(set) var allProjectIDs: Set<Int> = []
    public private(set) var allTaskIDs: Set<Int> = []

    public init(_ entries: [TrackedEntry]) {
        struct Combination: Hashable {
            var project: Int
            var task: Int
            var client: Int?
        }

        // Entries repeat a handful of project, task and client combinations thousands of times.
        var seen = Set<Combination>()
        var clientsByID: [Int: Reference] = [:]
        for entry in entries {
            guard seen.insert(Combination(project: entry.project.id, task: entry.task.id, client: entry.client?.id)).inserted else {
                continue
            }
            if projectsByID[entry.project.id] == nil { projectsByID[entry.project.id] = entry.project }
            if tasksByID[entry.task.id] == nil { tasksByID[entry.task.id] = entry.task }
            taskIDsByProject[entry.project.id, default: []].insert(entry.task.id)
            if let client = entry.client {
                if clientsByID[client.id] == nil { clientsByID[client.id] = client }
                projectIDsByClient[client.id, default: []].insert(entry.project.id)
                taskIDsByClient[client.id, default: []].insert(entry.task.id)
            }
        }
        projects = projectsByID.values.sorted(by: Self.order)
        clients = clientsByID.values.sorted(by: Self.order)
        tasks = tasksByID.values.sorted(by: Self.order)
        allProjectIDs = Set(projectsByID.keys)
        allTaskIDs = Set(tasksByID.keys)
    }

    public static func order(_ lhs: Reference, _ rhs: Reference) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
