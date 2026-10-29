import SwiftUI

/// A first-run empty state that can recover directly when the initial history load fails.
struct HistoryUnavailableView: View {
    @Environment(HistoryModel.self) private var history

    let systemImage: String

    var body: some View {
        if let failure = history.failure {
            ContentUnavailableView {
                Label("Couldn’t load entries", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            } actions: {
                Button {
                    Task { await history.refresh() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .disabled(history.isRefreshing)
            }
        } else {
            ContentUnavailableView(
                "No entries yet",
                systemImage: systemImage,
                description: Text("Entries from Harvest appear here once connected.")
            )
        }
    }
}
