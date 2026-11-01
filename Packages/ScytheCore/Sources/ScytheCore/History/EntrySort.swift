import Foundation

public enum EntrySortColumn: Sendable, CaseIterable {
    case date, client, project, task, hours, notes
}

public struct EntrySortKey: Sendable, Equatable {
    public var column: EntrySortColumn
    public var ascending: Bool

    public init(_ column: EntrySortColumn, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }
}

/// Sorts entries by table column.
///
/// `KeyPathComparator` runs a locale-aware compare on every one of n log n comparisons (135 ms
/// over two years of entries). Here each distinct text is ranked once and rows are ordered by
/// integer, in the same order, with equal rows keeping the order they came in.
public enum EntrySort {
    public static func sorted(_ entries: [TrackedEntry], by keys: [EntrySortKey]) -> [TrackedEntry] {
        guard entries.count > 1, !keys.isEmpty else { return entries }
        let comparisons = keys.map { comparison(for: $0, over: entries) }
        let order = entries.indices.sorted { lhs, rhs in
            for compare in comparisons {
                let result = compare(lhs, rhs)
                if result != 0 { return result < 0 }
            }
            return lhs < rhs
        }
        return order.map { entries[$0] }
    }

    private static func comparison(for key: EntrySortKey, over entries: [TrackedEntry]) -> (Int, Int) -> Int {
        let direction = key.ascending ? 1 : -1
        switch key.column {
        case .date:
            let days = entries.map { $0.spentDate.dayNumber }
            return { direction * compare(days[$0], days[$1]) }
        case .hours:
            let hours = entries.map(\.bankedHours)
            return { direction * compare(hours[$0], hours[$1]) }
        case .client:
            let ranks = textRanks(entries.map { $0.client?.name ?? "" })
            return { direction * compare(ranks[$0], ranks[$1]) }
        case .project:
            let ranks = textRanks(entries.map(\.project.name))
            return { direction * compare(ranks[$0], ranks[$1]) }
        case .task:
            let ranks = textRanks(entries.map(\.task.name))
            return { direction * compare(ranks[$0], ranks[$1]) }
        case .notes:
            let ranks = textRanks(entries.map { $0.notes ?? "" })
            return { direction * compare(ranks[$0], ranks[$1]) }
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> Int {
        lhs < rhs ? -1 : (rhs < lhs ? 1 : 0)
    }

    /// One rank per entry; texts that compare as the same share a rank.
    private static func textRanks(_ texts: [String]) -> [Int] {
        var slot: [String: Int] = [:]
        var distinct: [String] = []
        let slots = texts.map { text -> Int in
            if let known = slot[text] { return known }
            slot[text] = distinct.count
            distinct.append(text)
            return distinct.count - 1
        }

        let ordered = distinct.indices.sorted { distinct[$0].localizedStandardCompare(distinct[$1]) == .orderedAscending }
        var rankOfSlot = [Int](repeating: 0, count: distinct.count)
        var rank = 0
        for (position, index) in ordered.enumerated() {
            if position > 0, distinct[ordered[position - 1]].localizedStandardCompare(distinct[index]) != .orderedSame {
                rank += 1
            }
            rankOfSlot[index] = rank
        }
        return slots.map { rankOfSlot[$0] }
    }
}
