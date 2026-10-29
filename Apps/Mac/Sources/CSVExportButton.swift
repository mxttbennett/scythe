import AppKit
import ScytheCore
import SwiftUI
import UniformTypeIdentifiers

struct CSVExportButton: View {
    let rows: [TrackedEntry]

    var body: some View {
        Button(action: export) {
            Label("Export CSV", systemImage: "square.and.arrow.up")
        }
        .disabled(rows.isEmpty)
        .help("Export what is shown as CSV")
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "scythe-entries-\(CalendarDate.today()).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVExport.entries(rows).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
