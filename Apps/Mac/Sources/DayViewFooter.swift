import ScytheCore
import SwiftUI

struct DayViewFooter: View {
    @Environment(\.uiScale) private var uiScale

    @Binding var isShowingTimeSummary: Bool
    let format: HoursFormat
    let weekStart: Weekday
    let openDesktop: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8 * uiScale) {
            SyncStatusLabel()
            Button {
                isShowingTimeSummary = true
            } label: {
                Image(systemName: "info.circle")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Time summary")
            .accessibilityLabel("Time summary")
            .contentShape(.rect)
            .popover(isPresented: $isShowingTimeSummary, arrowEdge: .bottom) {
                TimeSummaryPopover(format: format, weekStart: weekStart)
            }

            Spacer()

            Button(action: openDesktop) {
                Image(systemName: "macwindow")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Open the Scythe window")
            .accessibilityLabel("Open the Scythe window")
            .contentShape(.rect)
            .keyboardShortcut("1")

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
            .contentShape(.rect)
            .keyboardShortcut(",")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .uiFrame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Quit Scythe")
            .accessibilityLabel("Quit Scythe")
            .contentShape(.rect)
            .keyboardShortcut("q")
        }
        .uiFont(.caption)
    }
}
