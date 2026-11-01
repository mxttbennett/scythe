import Foundation

public extension Sequence where Element == TimerTarget {
    /// The targets whose client, project and task names between them contain every word of `query`, in their given order.
    func matching(_ query: String) -> [TimerTarget] {
        let words = query.split(whereSeparator: \.isWhitespace).map { SearchIndex.fold(String($0)) }
        guard !words.isEmpty else { return Array(self) }
        let needles = SearchIndex.needles(for: words)
        return filter { target in
            let haystack = SearchIndex.fold(
                [target.client?.name, target.project.name, target.task.name].compactMap { $0 }.joined(separator: " ")
            )
            return SearchIndex.contains(all: needles, in: haystack)
        }
    }
}
