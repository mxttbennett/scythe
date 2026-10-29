import SwiftUI

/// A colour that depends only on the name it labels, so the same client, project or task
/// looks the same in every view and on every launch.
///
/// Swift's own `hashValue` changes on every launch, so this uses FNV-1a.
enum HashedColor {
    enum Kind: String {
        case client, project, task
    }

    struct Components: Hashable {
        var hue: Double
        var saturation: Double
        var brightness: Double
    }

    private static let tiers: [(saturation: Double, brightness: Double)] = [(0.60, 1.00), (0.85, 0.72), (0.45, 0.88), (0.78, 0.88)]
    private static let hues = 36

    static func components(for name: String, kind: Kind) -> Components {
        let slot = Int(fnv1a("\(kind.rawValue):\(name)") % UInt64(hues * tiers.count))
        let tier = tiers[slot / hues]
        return Components(hue: Double(slot % hues) / Double(hues), saturation: tier.saturation, brightness: tier.brightness)
    }

    static func color(for name: String, kind: Kind) -> Color {
        let c = components(for: name, kind: kind)
        return Color(hue: c.hue, saturation: c.saturation, brightness: c.brightness)
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hash
    }
}

/// A name with its hashed colour dot in front. Font and text colour come from the caller.
struct DotLabel: View {
    @Environment(\.uiScale) private var uiScale
    let name: String
    let kind: HashedColor.Kind
    var maxLines = 1

    var body: some View {
        HStack(spacing: 5 * uiScale) {
            Circle()
                .fill(HashedColor.color(for: name, kind: kind))
                .frame(width: 7 * uiScale, height: 7 * uiScale)
                .accessibilityHidden(true)
            Text(name).lineLimit(maxLines)
        }
    }
}
