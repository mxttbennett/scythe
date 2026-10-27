import AppKit
import ScytheCore
import SwiftUI

/// Puts the date format choice on the right-click menu of the explorer's Date column header.
///
/// SwiftUI's `Table` has no header menu, but on macOS it is an `NSTableView`, and its header view takes one.
struct DateColumnMenu: NSViewRepresentable {
    let preference: EntryDateFormatPreference

    func makeCoordinator() -> Coordinator { Coordinator(preference: preference) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(from: view)
    }

    static func fill(_ menu: NSMenu, for preference: EntryDateFormatPreference, target: AnyObject?) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Date format", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for format in EntryDateFormat.allCases {
            let item = NSMenuItem(
                title: format.formatted(.today()),
                action: #selector(Coordinator.choose(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = format.rawValue
            item.state = format == preference.format ? .on : .off
            menu.addItem(item)
        }
    }

    static func choose(_ item: NSMenuItem, in preference: EntryDateFormatPreference) {
        guard let raw = item.representedObject as? String, let format = EntryDateFormat(rawValue: raw) else { return }
        preference.format = format
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        private let preference: EntryDateFormatPreference
        private let menu = NSMenu(title: "Date format")
        private weak var table: NSTableView?

        init(preference: EntryDateFormatPreference) {
            self.preference = preference
            super.init()
            menu.delegate = self
        }

        /// The table is not in the window yet on the first update, so this keeps looking for a moment.
        func attach(from view: NSView, attempts: Int = 10) {
            Task { @MainActor [weak self, weak view] in
                guard let self, let view else { return }
                if let table = view.window?.contentView?.tables.first(where: \.hasDateColumn) {
                    self.table = table
                    table.headerView?.menu = self.menu
                } else if attempts > 0 {
                    try? await Task.sleep(for: .milliseconds(200))
                    self.attach(from: view, attempts: attempts - 1)
                }
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard clickedColumnIsDate else { return }
            DateColumnMenu.fill(menu, for: preference, target: self)
        }

        @objc func choose(_ item: NSMenuItem) {
            DateColumnMenu.choose(item, in: preference)
        }

        private var clickedColumnIsDate: Bool {
            guard let header = table?.headerView, let event = NSApp.currentEvent else { return false }
            let column = header.column(at: header.convert(event.locationInWindow, from: nil))
            return table?.tableColumns.indices.contains(column) == true
                && table?.tableColumns[column].headerCell.stringValue == "Date"
        }
    }
}

private extension NSView {
    /// Every table below this view. The window's sidebar list is one too, so the explorer's has to be told apart.
    var tables: [NSTableView] {
        subviews.flatMap { subview -> [NSTableView] in
            if let table = subview as? NSTableView { return [table] }
            return subview.tables
        }
    }
}

private extension NSTableView {
    var hasDateColumn: Bool {
        tableColumns.contains { $0.headerCell.stringValue == "Date" }
    }
}
