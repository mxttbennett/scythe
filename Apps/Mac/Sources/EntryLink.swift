import SwiftUI

/// The icon that opens the link Harvest keeps on an entry logged from another tool.
struct EntryLink: View {
    let url: URL
    var style: Font.TextStyle = .callout

    var body: some View {
        Link(destination: url) {
            Image(systemName: "link")
                .uiFont(style)
        }
        .help("Open \(url.host() ?? url.absoluteString)")
        .accessibilityLabel("Open linked ticket")
    }
}
