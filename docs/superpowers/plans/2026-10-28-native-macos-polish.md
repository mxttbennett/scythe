# Native macOS polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Scythe's desktop workspace, menu bar panel, and entry workflows feel like one cohesive, responsive macOS app.

**Architecture:** Preserve the existing SwiftUI and AppKit ownership boundaries. Refine shared system-native treatments where multiple views use them, then tune each surface in its owning view. Keep data flow, persistence, and current actions unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit, macOS 26, XcodeGen.

---

## File map

- `Apps/Mac/Sources/DesktopWindow.swift`: desktop window chrome, sidebar, toolbar, and search placement.
- `Apps/Mac/Sources/FilterBar.swift`: shared Explorer and Analytics filters.
- `Apps/Mac/Sources/ExplorerView.swift`: history table, empty states, and footer summary.
- `Apps/Mac/Sources/ExplorerLive.swift`: live durations and the Explorer summary.
- `Apps/Mac/Sources/AnalyticsView.swift`: statistics and charts.
- `Apps/Mac/Sources/TimesheetView.swift`: weekly grid and editable hour cells.
- `Apps/Mac/Sources/DayView.swift`: menu bar panel hierarchy and day controls.
- `Apps/Mac/Sources/EntryRow.swift`: selected/running entry presentation and inline actions.
- `Apps/Mac/Sources/TargetPicker.swift`: searchable quick-entry project list and keyboard scrolling.
- `Apps/Mac/Sources/GlassSurface.swift`: shared semantic glass and text treatments.
- `Apps/Mac/Sources/AddEntryForm.swift` and `Apps/Mac/Sources/ExplorerView.swift`: entry forms and the edit sheet. `EditEntryPanelController.swift` owns the separate AppKit editor window.
- `Apps/Mac/Sources/SettingsView.swift`: grouped settings and native form controls.

## Task 1: Unify desktop workspace controls

**Files:** `DesktopWindow.swift`, `FilterBar.swift`

- [x] Keep search and primary actions in the window toolbar.
- [x] Group date, client, project, task, and billable filters as one compact native control area.
- [x] Keep saved-query and reset actions adjacent to the active filters; avoid showing inactive cleanup actions.
- [ ] Check the layout at the minimum window width and at a wide window.

## Task 2: Improve reading rhythm across desktop views

**Files:** `ExplorerView.swift`, `AnalyticsView.swift`, `TimesheetView.swift`

- [ ] Tune Explorer column widths and row content hierarchy for legibility at the minimum supported width.
- [x] Keep its native table sorting, selection, context menu, keyboard actions, and summary.
- [x] Replace repeated card-like grouping in Analytics with a clearer native hierarchy for totals and charts.
- [ ] Align Timesheet headers, day totals, and editable cells with the same spacing and numeric treatment.
- [ ] Retain explicit empty and loading states for each view.

## Task 3: Clarify timer and entry interactions

**Files:** `DayView.swift`, `EntryRow.swift`, `GlassSurface.swift`

- [x] Give the active timer and selected entry distinct, consistent emphasis.
- [x] Keep the daily breakdown visually secondary to the entry list and timer actions.
- [x] Use system-adaptive material and text colors in light and dark appearance.
- [x] Add brief action feedback only where it explains a state change; respect Reduce Motion and keep timer ticks visually steady.
- [x] Preserve row selection, inline editing, keyboard navigation, and VoiceOver actions.

## Task 4: Align settings and entry forms

**Files:** `SettingsView.swift`, `AddEntryForm.swift`, `ExplorerView.swift`, `EditEntryPanelController.swift`

- [x] Keep native grouped forms and menus while aligning control spacing and label hierarchy.
- [x] Ensure focus, save, cancel, and destructive actions read clearly in both appearances.
- [x] Preserve validation, dismissal, and keyboard shortcuts.

## Task 5: Build and review the result

- [x] Build `Scythe.xcodeproj` scheme `Scythe` for macOS.
- [ ] Review the desktop workspace and menu panel in light and dark appearance.
- [ ] Check the minimum and wide desktop window sizes, selected/running timer states, and editor open/close feedback.
- [ ] Compare the rendered result against the design spec and remove any treatment that feels decorative or inconsistent.

## Coverage review

- Desktop search and filters: Task 1.
- Explorer, Analytics, and Timesheet hierarchy: Task 2.
- Running/selected entry, shared appearance, motion, keyboard, and VoiceOver: Task 3.
- Settings and entry forms: Task 4.
- Build and full visual review: Task 5.
