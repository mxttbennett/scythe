import SwiftUI
import Testing
@testable import Scythe

@Suite("Glass tint")
struct GlassTintTests {
    @Test("dark mode keeps a stronger surface tint")
    func darkIsHeavier() {
        // Act & Assert
        #expect(GlassTint.opacity(for: .dark) > GlassTint.opacity(for: .light))
    }

    @Test("both themes tint the surface enough to separate it from the window behind")
    func bothThemesUseAReadableTint() {
        // Act & Assert
        #expect(GlassTint.opacity(for: .light) >= 0.4)
        #expect(GlassTint.opacity(for: .dark) >= 0.65)
    }

    @Test("secondary text stands out more than tertiary labels")
    func secondaryInkIsStronger() {
        // Act & Assert
        #expect(GlassInk.secondaryOpacity > GlassInk.tertiaryOpacity)
        #expect(GlassInk.tertiaryOpacity >= 0.7)
    }

    @Test("the glass still lets the window behind show through")
    func neverFullyOpaque() {
        // Act & Assert
        for scheme in [ColorScheme.light, .dark] {
            #expect((0.05..<0.9).contains(GlassTint.opacity(for: scheme)))
        }
    }
}
