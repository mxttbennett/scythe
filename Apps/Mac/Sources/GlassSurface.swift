import SwiftUI

extension View {
    func glassSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(UIScalePreference.self) private var uiScale

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
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.12), in: shape)
            .clipShape(shape)
            .glassEffect(.regular, in: shape)
    }
}
