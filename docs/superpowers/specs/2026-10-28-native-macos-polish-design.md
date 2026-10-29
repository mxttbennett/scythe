# Native macOS polish

## Problem

Scythe already uses SwiftUI and AppKit controls, but the menu bar panel, desktop workspace, and entry forms do not yet feel like parts of one finished Mac app. Explorer puts many filters and columns in view at once. The timer panel has to balance a dense day list with the running entry, budget, and daily summary. Analytics and Timesheet use different spacing and grouping patterns.

## Design

Keep the macOS window, sidebar, toolbar, table, menus, forms, and charts native. Use the system's adaptive window and control materials, primary and secondary text styles, separator colors, and accent color. Use SF system text styles for hierarchy and tabular digits for durations and totals. Keep client, project, and task identity in the existing semantic colors, with labels so color is never the only cue.

Treat the desktop window as one workspace. Keep navigation in the sidebar, search and primary actions in the toolbar, and filters adjacent to the content they control. Give Explorer a calmer reading rhythm through purposeful column widths, legible row spacing, and a summary that remains easy to find. Keep the native table's sorting, selection, keyboard navigation, and context menu behavior.

Give the menu bar panel one clear priority: the current day and active timer. Preserve the existing list and inline editing, while making the selected and running entry states consistent and easy to distinguish. Keep the daily breakdown secondary to entry actions. Use the same emphasis for active time in the desktop views where it helps orientation.

Use one spacing and grouping vocabulary across Analytics, Timesheet, settings, and entry forms. Prefer native grouped sections and toolbar controls over repeated decorative cards. Keep forms compact, align labels with controls, and let system focus rings and control states show where input goes.

Motion should confirm a user action, such as switching days or opening an editor. Keep it brief and avoid animating the timer digits on every tick. Respect Reduce Motion. Maintain visible keyboard focus, existing shortcuts, VoiceOver labels, light and dark appearance, and the current scaled UI preference.

## Ownership and data flow

- `DesktopRootView` owns the desktop navigation, toolbar, and shared search/filter placement.
- `FilterBar` owns date, facet, and billable filters shared by Explorer and Analytics.
- `ExplorerView`, `AnalyticsView`, and `TimesheetView` own their respective content and empty states.
- `ExplorerLive` owns live durations and the Explorer summary; `TargetPicker` owns searchable project selection and keyboard scrolling.
- `DayView` and `EntryRow` own the menu bar timer panel and daily entry interactions.
- `GlassSurface`, `GlassInk`, and the existing scaling helpers own shared surface and text treatments.
- `AddEntryForm` and the edit-entry sheet own entry creation and editing.

Share a treatment only when multiple surfaces use the same hierarchy or interaction. Keep each view responsible for its content and state.

## Interaction and accessibility

Keep current mouse, keyboard, and VoiceOver paths intact. Add no action that is available only on hover. Keep focus visible, preserve existing shortcut labels, and retain native focus behavior in fields and menus. Use system semantic colors for readable contrast in both appearances. Check the Reduce Motion setting before adding custom transitions.

## Scope

Polish the desktop workspace, menu bar panel, settings, Analytics, Timesheet, and entry creation/editing. Preserve the existing Harvest behavior, stored preferences, navigation, and keyboard shortcuts. Do not introduce a custom color theme, new persistence, or a new navigation model.

## Acceptance criteria

- Main window, menu panel, settings, and entry forms share a clear system-native hierarchy in light and dark appearance.
- Explorer filters read as one related control area, and the table remains scannable without losing native table behavior.
- Running and selected entries have consistent, distinguishable states in the menu panel and desktop workspace.
- Analytics, Timesheet, and settings group related information with consistent spacing and system controls.
- Any added motion responds to user actions, avoids continuous timer-tick animation, and respects Reduce Motion.
- Existing keyboard, VoiceOver, scaling, editing, and timer workflows continue to work.
