import SwiftUI

extension View {
    func glassSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

/// How much of the window colour sits under the glass. The glass alone let a bright window behind
/// wash out light text in dark mode, so dark mode tints more heavily.
enum GlassTint {
    static func opacity(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.5 : 0.2
    }
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
