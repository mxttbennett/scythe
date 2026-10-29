import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that captures the next key combination pressed.
///
/// A local event monitor is enough — the Settings window is key while recording —
/// and it avoids hand-rolling an `NSView` just to win first responder.
struct ShortcutRecorder: View {
    @Binding var shortcut: HotKeyShortcut

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecording ? "Press keys…" : shortcut.display) {
                isRecording ? stop() : start()
            }
            .font(.body.monospaced())
            .frame(minWidth: 90)
            .accessibilityLabel("Quick entry shortcut")
            .accessibilityValue(isRecording ? "Recording" : shortcut.display)
            .accessibilityHint(
                isRecording
                    ? "Press a key combination that includes Control, Option, or Command. Press Escape to cancel."
                    : "Activate to record a new shortcut."
            )
            .help(isRecording ? "Press a key combination. Escape cancels." : "Change the quick entry shortcut")

            if isRecording {
                Button("Cancel") { stop() }
                    .buttonStyle(.link)
            }

            if rejected {
                Text("Needs ⌃, ⌥ or ⌘")
                    .font(.caption)
                    .foregroundStyle(GlassInk.secondary)
                    .accessibilityLabel("A shortcut must include Control, Option, or Command.")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        rejected = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape leaves the existing shortcut alone.
            guard event.keyCode != UInt16(kVK_Escape) else {
                stop()
                return nil
            }
            if let captured = HotKeyShortcut(event: event) {
                shortcut = captured
                stop()
            } else {
                rejected = true
            }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
