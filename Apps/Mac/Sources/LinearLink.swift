import AppKit
import SwiftUI

/// Sends Linear links to the Linear desktop app when it is installed.
enum LinearLink {
    /// The pages inside a workspace the desktop app opens from a `linear://` link. Anything else on
    /// linear.app, such as its docs or changelog, is a web page.
    private static let workspacePages: Set<String> = ["issue", "project", "document", "initiative", "cycle", "view", "team"]

    static func desktopURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host()?.lowercased() == "linear.app"
        else { return nil }
        let parts = url.path(percentEncoded: true).split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, workspacePages.contains(String(parts[1])) else { return nil }
        var text = "linear://" + parts.joined(separator: "/")
        if let query = url.query(percentEncoded: true) { text += "?" + query }
        if let fragment = url.fragment(percentEncoded: true) { text += "#" + fragment }
        return URL(string: text)
    }

    /// The address to open instead of `url`, or nil to open it as it is.
    static func route(_ url: URL, isInstalled: Bool) -> URL? {
        isInstalled ? desktopURL(for: url) : nil
    }

    /// Asked at the click, not when a row is drawn: the app can be installed or removed while Scythe runs.
    static var isDesktopAppInstalled: Bool {
        guard let probe = URL(string: "linear://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }
}

extension View {
    /// Opens Linear links in the Linear desktop app, and every other link as usual.
    func opensLinearInDesktopApp() -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard let desktop = LinearLink.route(url, isInstalled: LinearLink.isDesktopAppInstalled),
                  NSWorkspace.shared.open(desktop)
            else { return .systemAction }
            return .handled
        })
    }
}
