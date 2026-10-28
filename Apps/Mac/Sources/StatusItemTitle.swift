import AppKit

/// What the menu bar item says beside its glyph.
@MainActor
enum StatusItemTitle {
    /// The total belongs to the day it counts, so a panel paged back to another day shows the time alone.
    static func attributed(
        style: StatusItemStyle,
        project: String,
        hours: String,
        total: String,
        isToday: Bool
    ) -> NSAttributedString {
        let shown = style == .stacked && !isToday ? StatusItemStyle.time : style
        return NSAttributedString(
            string: shown.title(project: project, hours: hours, total: total),
            attributes: shown == .stacked ? stackedAttributes : singleLineAttributes
        )
    }

    /// Monospaced digits, so a ticking total does not jiggle the whole menu bar.
    private static let singleLineAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    ]

    /// Two lines squeezed into the menu bar's height, right-aligned so the digits line up.
    private static let stackedAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.minimumLineHeight = 10
        paragraph.maximumLineHeight = 10
        return [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .paragraphStyle: paragraph,
            .baselineOffset: -5
        ]
    }()
}
