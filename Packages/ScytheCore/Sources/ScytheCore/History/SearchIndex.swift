import Foundation

/// The text each entry is searched on, folded once so a keystroke compares plain bytes.
///
/// Folding case and accents per comparison cost about 33 ms over two years of entries; folded
/// text cut that to 6, and `memmem` over the bytes to under 1.
public struct SearchIndex: Sendable {
    private let haystacks: [TrackedEntry.ID: [UInt8]]

    public init(_ entries: [TrackedEntry]) {
        var folded: [String: String] = [:]
        func fold(_ text: String) -> String {
            if let known = folded[text] { return known }
            let result = Self.fold(text)
            folded[text] = result
            return result
        }
        var haystacks: [TrackedEntry.ID: [UInt8]] = [:]
        haystacks.reserveCapacity(entries.count)
        for entry in entries where haystacks[entry.id] == nil {
            haystacks[entry.id] = Array([entry.notes, entry.project.name, entry.client?.name, entry.task.name]
                .compactMap { $0 }.map(fold).joined(separator: " ").utf8)
        }
        self.haystacks = haystacks
    }

    /// Lowercased with accents removed and canonically composed, so equal text is equal bytes whichever way it was typed.
    static func fold(_ text: String) -> String {
        asciiLowercased(text)
            ?? text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .precomposedStringWithCanonicalMapping
    }

    /// Plain ASCII is nearly all of what people log, and lowering it by hand skips the Foundation call.
    private static func asciiLowercased(_ text: String) -> String? {
        var text = text
        return text.withUTF8 { bytes -> String? in
            guard bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
            return String(unsafeUninitializedCapacity: bytes.count) { buffer in
                for (offset, byte) in bytes.enumerated() {
                    buffer[offset] = byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte | 0x20 : byte
                }
                return bytes.count
            }
        }
    }

    private static func haystack(for entry: TrackedEntry) -> [UInt8] {
        Array(fold([entry.notes, entry.project.name, entry.client?.name, entry.task.name].compactMap { $0 }.joined(separator: " ")).utf8)
    }

    static func needles(for foldedWords: [String]) -> [[UInt8]] {
        foldedWords.map { Array($0.utf8) }
    }

    /// Whether every word is in the entry's text. An entry the index has not seen is folded on the spot.
    func matches(_ entry: TrackedEntry, needles: [[UInt8]]) -> Bool {
        let haystack = haystacks[entry.id] ?? Self.haystack(for: entry)
        return haystack.withUnsafeBufferPointer { Self.contains(all: needles, in: $0) }
    }

    /// Whether every word is in `haystack`, which must already be folded.
    static func contains(all needles: [[UInt8]], in haystack: String) -> Bool {
        var haystack = haystack
        return haystack.withUTF8 { contains(all: needles, in: $0) }
    }

    private static func contains(all needles: [[UInt8]], in text: UnsafeBufferPointer<UInt8>) -> Bool {
        needles.allSatisfy { needle in
            needle.isEmpty || needle.withUnsafeBufferPointer { word in
                text.count >= word.count && memmem(text.baseAddress, text.count, word.baseAddress, word.count) != nil
            }
        }
    }
}
