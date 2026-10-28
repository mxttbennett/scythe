# Searchable project and task selection

## Problem

The Add time entry form uses native menus for Project and Task. The project menu can contain many active assignments, so finding an item requires scrolling through a long list.

## Design

Replace both menus with searchable popovers. Opening either popover focuses an empty search field and shows the available choices in their existing order. Search matches every whitespace-separated query term without case or accent sensitivity. The project search matches client and project names; task search matches task names from the selected project's active task assignments only.

Choosing a project updates the draft and immediately opens the task picker. Choosing a task closes the picker and returns focus to Hours. Up and Down move the highlighted option, Return chooses it, and Escape closes the current picker. Empty results show a short message; clicking outside dismisses the popover.

The AddEntryForm is shared by the menu-bar panel and desktop window, so both receive the same behavior. The existing quick-entry palette and edit-entry dialog stay unchanged.

## Trade-offs

Separate pickers preserve the form's clear Project-then-Task structure while making selection searchable. A combined project/task palette would take less interaction for some choices but would mix two assignment levels in one result list.
