import Foundation

enum NoteLinks {
    // The pattern is a constant, so this cannot fail at runtime.
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Only text that was typed as a web address is linked: the detector also calls
    /// "README.md" and "example.com" links, and neither is one in a time-entry note.
    static func attributed(_ notes: String) -> AttributedString {
        var result = AttributedString(notes)
        guard notes.range(of: "http", options: .caseInsensitive) != nil else { return result }
        let text = notes as NSString
        for match in detector.matches(in: notes, range: NSRange(location: 0, length: text.length)) {
            guard let url = match.url,
                  text.substring(with: match.range).lowercased().hasPrefix("http"),
                  let range = Range(match.range, in: result)
            else { continue }
            result[range].link = url
            result[range].underlineStyle = .single
        }
        return result
    }
}
