import SwiftUI

extension View {
    /// Clips before the glass so rows scrolling under a corner do not poke past it.
    func glassSurface(cornerRadius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return clipShape(shape).glassEffect(.regular, in: shape)
    }
}
