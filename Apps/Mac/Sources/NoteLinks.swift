import Foundation

@MainActor
enum NoteLinks {
    private struct CachedValue {
        let attributed: AttributedString
        let byteCount: Int
    }

    // The pattern is a constant, so this cannot fail at runtime.
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static var cache: [String: CachedValue] = [:]
    private static var cacheOrder: [String] = []
    private static var cachedBytes = 0
    private static let cacheLimit = 512
    private static let byteLimit = 2_000_000

    /// Only text that was typed as a web address is linked: the detector also calls
    /// "README.md" and "example.com" links, and neither is one in a time-entry note.
    static func attributed(_ notes: String) -> AttributedString {
        if let cached = cache[notes] { return cached.attributed }

        var result = AttributedString(notes)
        if notes.range(of: "http", options: .caseInsensitive) != nil {
            let text = notes as NSString
            for match in detector.matches(in: notes, range: NSRange(location: 0, length: text.length)) {
                guard let url = match.url,
                      text.substring(with: match.range).lowercased().hasPrefix("http"),
                      let range = Range(match.range, in: result)
                else { continue }
                result[range].link = url
                result[range].underlineStyle = .single
            }
        }

        let byteCount = notes.utf8.count
        guard byteCount <= byteLimit else { return result }
        while cache.count >= cacheLimit || cachedBytes + byteCount > byteLimit {
            guard let oldest = cacheOrder.first else { break }
            cacheOrder.removeFirst()
            cachedBytes -= cache.removeValue(forKey: oldest)?.byteCount ?? 0
        }
        cache[notes] = CachedValue(attributed: result, byteCount: byteCount)
        cacheOrder.append(notes)
        cachedBytes += byteCount
        return result
    }
}
