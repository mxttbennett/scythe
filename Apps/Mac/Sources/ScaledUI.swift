import AppKit
import SwiftUI

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

extension View {
    func uiFont(_ style: Font.TextStyle, monospacedDigit: Bool = false) -> some View {
        modifier(UIFont(style: style, monospacedDigit: monospacedDigit))
    }

    func uiPadding(_ edges: Edge.Set, _ length: CGFloat) -> some View {
        modifier(UIPadding(edges: edges, length: length))
    }

    func uiPadding(_ length: CGFloat) -> some View {
        uiPadding(.all, length)
    }

    func uiFrame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        minWidth: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        modifier(UIFrame(width: width, height: height, minWidth: minWidth, alignment: alignment))
    }
}

/// Real fonts at the scaled size rather than a magnified bitmap: `scaleEffect` draws the
/// layout at 1× and stretches it, which is visibly soft on a Retina display.
private struct UIFont: ViewModifier {
    @Environment(\.uiScale) private var scale
    let style: Font.TextStyle
    let monospacedDigit: Bool

    func body(content: Content) -> some View {
        let size = NSFont.preferredFont(forTextStyle: style.appKit).pointSize * scale
        var font = Font.system(size: size, weight: style == .headline ? .bold : .regular)
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }
}

private struct UIPadding: ViewModifier {
    @Environment(\.uiScale) private var scale
    let edges: Edge.Set
    let length: CGFloat

    func body(content: Content) -> some View {
        content.padding(edges, length * scale)
    }
}

private struct UIFrame: ViewModifier {
    @Environment(\.uiScale) private var scale
    let width: CGFloat?
    let height: CGFloat?
    let minWidth: CGFloat?
    let alignment: Alignment

    func body(content: Content) -> some View {
        if let minWidth {
            content.frame(minWidth: minWidth * scale, alignment: alignment)
        } else {
            content.frame(width: width.map { $0 * scale }, height: height.map { $0 * scale }, alignment: alignment)
        }
    }
}

private extension Font.TextStyle {
    var appKit: NSFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
