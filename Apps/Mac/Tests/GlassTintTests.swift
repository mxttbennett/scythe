import SwiftUI
import Testing
@testable import Scythe

@Suite("Glass tint")
struct GlassTintTests {
    @Test("dark mode tints more heavily than light, because light text needs the contrast")
    func darkIsHeavier() {
        // Act & Assert
        #expect(GlassTint.opacity(for: .dark) > GlassTint.opacity(for: .light))
    }

    @Test("dark mode is mostly opaque so text over a bright window stays readable")
    func darkIsMostlyOpaque() {
        // Act & Assert
        #expect(GlassTint.opacity(for: .dark) >= 0.45)
    }

    @Test("the glass still lets the window behind show through")
    func neverFullyOpaque() {
        // Act & Assert
        for scheme in [ColorScheme.light, .dark] {
            #expect((0.05..<0.9).contains(GlassTint.opacity(for: scheme)))
        }
    }
}
