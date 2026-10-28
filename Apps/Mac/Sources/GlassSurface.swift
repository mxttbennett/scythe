import SwiftUI

extension View {
    func glassSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

/// Keeps windows behind the glass from washing out text.
enum GlassTint {
    static func opacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.68 : 0.4
    }
}

enum GlassInk {
    static let secondaryOpacity = 0.86
    static let tertiaryOpacity = 0.72
    static var secondary: AnyShapeStyle { AnyShapeStyle(Color.primary.opacity(secondaryOpacity)) }
    static var tertiary: AnyShapeStyle { AnyShapeStyle(Color.primary.opacity(tertiaryOpacity)) }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(UIScalePreference.self) private var uiScale
    @Environment(\.colorScheme) private var colorScheme

    /// Native controls draw at a fixed height unless told otherwise, and would clip their
    /// own scaled text.
    private var controlSize: ControlSize {
        switch uiScale.scale {
        case ..<0.85: .small
        case ..<1.25: .regular
        case ..<1.75: .large
        default: .extraLarge
        }
    }

    /// Clips before the glass so rows scrolling under a corner do not poke past it.
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius * uiScale.scale, style: .continuous)
        content
            .environment(\.uiScale, uiScale.scale)
            .controlSize(controlSize)
            .background(Color(nsColor: .windowBackgroundColor).opacity(GlassTint.opacity(for: colorScheme)), in: shape)
            .clipShape(shape)
            .glassEffect(.regular, in: shape)
    }
}
