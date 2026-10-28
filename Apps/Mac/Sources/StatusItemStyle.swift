import Foundation

/// How much the menu bar item shows beside its glyph.
enum StatusItemStyle: String, CaseIterable, Identifiable {
    case iconOnly
    case time
    case projectAndTime
    case stacked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconOnly: "Icon only"
        case .time: "Icon and time"
        case .projectAndTime: "Icon, project and time"
        case .stacked: "Icon, entry time over day total"
        }
    }

    func title(project: String, hours: String, total: String) -> String {
        switch self {
        case .iconOnly: ""
        case .time: " \(hours)"
        case .projectAndTime: " \(Self.shortened(project))  \(hours)"
        case .stacked: "\(hours)\n\(total)"
        }
    }

    /// Long project names would crowd out everything else in the menu bar.
    private static func shortened(_ name: String, limit: Int = 18) -> String {
        guard name.count > limit else { return name }
        return name.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

@MainActor
@Observable
final class StatusItemStylePreference {
    private static let defaultsKey = "statusItemStyle"

    var style: StatusItemStyle {
        didSet {
            guard style != oldValue else { return }
            defaults.set(style.rawValue, forKey: Self.defaultsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: Self.defaultsKey).flatMap(StatusItemStyle.init(rawValue:)) ?? .time
    }
}
