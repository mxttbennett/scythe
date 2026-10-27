import AppKit
import SwiftUI

@MainActor
@Observable
final class UIScalePreference {
    static let steps: [CGFloat] = [0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.75, 2.0]
    private static let defaultsKey = "uiScale"

    private(set) var scale: CGFloat {
        didSet { defaults.set(Double(scale), forKey: Self.defaultsKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = CGFloat(defaults.double(forKey: Self.defaultsKey))
        scale = Self.steps.contains(stored) ? stored : 1
    }

    func zoomIn() {
        scale = Self.steps.first { $0 > scale } ?? scale
    }

    func zoomOut() {
        scale = Self.steps.last { $0 < scale } ?? scale
    }

    func reset() {
        scale = 1
    }

    /// Calls `handler` after every change, a turn late: the change is announced before
    /// it is applied, and the handler needs the layout that follows it.
    func observe(_ handler: @escaping @MainActor () -> Void) {
        withObservationTracking {
            _ = scale
        } onChange: { [weak self] in
            Task { @MainActor in
                handler()
                self?.observe(handler)
            }
        }
    }
}

extension NSWindow {
    func fitToContent() {
        guard let view = contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let fitted = view.fittingSize
        if fitted.width > 0, fitted.height > 0 {
            setContentSize(fitted)
        }
    }
}
