import ScytheCore
import SwiftUI

enum ChoiceSearch {
    struct Signature<ID: Hashable>: Equatable {
        let id: ID
        let text: String
    }

    struct IndexedItem<Item> {
        let item: Item
        let foldedText: String
    }

    static func index<Item>(_ items: [Item], searchText: (Item) -> String) -> [IndexedItem<Item>] {
        items.map { IndexedItem(item: $0, foldedText: fold(searchText($0))) }
    }

    static func filter<Item>(
        _ indexedItems: [IndexedItem<Item>],
        query: String
    ) -> [Item] {
        let words = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !words.isEmpty else { return indexedItems.map(\.item) }
        return indexedItems.compactMap { indexed in
            words.allSatisfy { indexed.foldedText.contains($0) } ? indexed.item : nil
        }
    }

    static func filter<Item>(
        _ items: [Item],
        query: String,
        searchText: (Item) -> String
    ) -> [Item] {
        filter(index(items, searchText: searchText), query: query)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

struct SearchableChoiceMenu<Item: Identifiable>: View where Item.ID: Hashable {
    private struct ItemRevision: Equatable {
        let count: Int
        let source: Int?
    }

    @Environment(\.uiScale) private var uiScale
    @Environment(\.menuBarPickerPopoverTracking) private var trackPopover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let current: String
    let items: [Item]
    var itemsRevision: Int? = nil
    let selectedID: Item.ID?
    var selectedIDs: Set<Item.ID>? = nil
    let searchPrompt: String
    let emptyMessage: String
    @Binding var isPresented: Bool
    let label: (Item) -> String
    let searchText: (Item) -> String
    let choose: (Item) -> Void
    var keepsOpenOnSelection = false
    var clearSelection: (() -> Void)? = nil
    var clearSelectionTitle = "Clear Selection"
    var showsTitle = true
    var usesButtonBackground = true
    var fillsAvailableWidth = true
    var anchorSystemImage: String? = nil
    @State private var query = ""
    @State private var highlightedID: Item.ID?
    @State private var indexedItems: [ChoiceSearch.IndexedItem<Item>] = []
    @State private var filteredItems: [Item] = []
    @FocusState private var isSearchFocused: Bool

    private var itemRevision: ItemRevision {
        ItemRevision(count: items.count, source: itemsRevision)
    }

    private var highlightedIndex: Int {
        guard let highlightedID,
              let index = filteredItems.firstIndex(where: { $0.id == highlightedID })
        else { return 0 }
        return index
    }

    private var choiceListHeight: CGFloat {
        min(260 * uiScale, CGFloat(min(filteredItems.count, 7)) * 36 * uiScale)
    }

    var body: some View {
        HStack(spacing: 8 * uiScale) {
            if showsTitle {
                Text(title)
                    .uiFont(.callout)
                    .foregroundStyle(GlassInk.secondary)
                    .uiFrame(width: 56, alignment: .leading)
            }
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 6 * uiScale) {
                    if let anchorSystemImage {
                        Label(anchorTitle, systemImage: anchorSystemImage)
                            .uiFont(.callout)
                            .lineLimit(1)
                    } else {
                        Text(anchorTitle)
                            .uiFont(.callout)
                            .lineLimit(1)
                    }
                    if anchorSystemImage == nil {
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .uiFont(.caption2)
                            .opacity(0.6)
                    }
                }
                .uiPadding(.horizontal, usesButtonBackground ? 8 : 0)
                .uiPadding(.vertical, usesButtonBackground ? 4 : 0)
                .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
                .background(
                    usesButtonBackground ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6 * uiScale)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(anchorTitle)
            .help(anchorTitle)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8 * uiScale) {
                    HStack(spacing: 6 * uiScale) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(GlassInk.secondary)
                        TextField(searchPrompt, text: $query)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .onSubmit(chooseHighlighted)
                        if !query.isEmpty {
                            Button {
                                query = ""
                                isSearchFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(GlassInk.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear search")
                            .accessibilityLabel("Clear search")
                            .transition(.opacity)
                        }
                    }
                    .uiPadding(.horizontal, 9)
                    .uiPadding(.vertical, 7)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8 * uiScale))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: query.isEmpty)

                    if filteredItems.isEmpty {
                        Text(emptyMessage)
                            .uiFont(.callout)
                            .foregroundStyle(GlassInk.secondary)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 2 * uiScale) {
                                    ForEach(filteredItems) { item in
                                        choiceRow(item)
                                            .id(item.id)
                                    }
                                }
                            }
                            .frame(height: choiceListHeight)
                            .onChange(of: highlightedID) { scrollToHighlight(proxy) }
                        }
                    }

                    if let clearSelection, selectedIDs?.isEmpty == false || selectedID != nil {
                        Divider()
                        Button(clearSelectionTitle) {
                            clearSelection()
                            isSearchFocused = true
                        }
                            .buttonStyle(.plain)
                            .uiFont(.callout)
                            .foregroundStyle(GlassInk.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .uiPadding(.horizontal, 8)
                    }
                }
                .uiPadding(10)
                .frame(width: 320 * uiScale)
                .onKeyPress(.downArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -1) }
                .onKeyPress(.escape, phases: .down) { _ in
                    if query.isEmpty {
                        isPresented = false
                    } else {
                        query = ""
                        isSearchFocused = true
                    }
                    return .handled
                }
                .onAppear {
                    rebuildSearchIndex()
                    isSearchFocused = true
                }
            }
            .onChange(of: itemRevision) { _, _ in
                guard isPresented else { return }
                rebuildSearchIndex()
                if !filteredItems.contains(where: { $0.id == highlightedID }) {
                    highlightedID = filteredItems.first?.id
                }
            }
            .onChange(of: query) { _, _ in
                updateFilteredItems()
                highlightedID = filteredItems.first?.id
            }
            .onChange(of: isPresented) { _, presented in
                trackPopover(presented)
                isSearchFocused = presented
                guard presented else { return }
                query = ""
                highlightedID = items.first?.id
            }
        }
    }

    private var anchorTitle: String {
        guard let selectedIDs else { return current }
        return selectedIDs.isEmpty ? title : "\(title) · \(selectedIDs.count.formatted())"
    }

    private func rebuildSearchIndex() {
        indexedItems = ChoiceSearch.index(items, searchText: searchText)
        updateFilteredItems()
    }

    private func updateFilteredItems() {
        filteredItems = ChoiceSearch.filter(indexedItems, query: query)
    }

    private func choiceRow(_ item: Item) -> some View {
        let isHighlighted = item.id == highlightedID
        let isSelected = selectedIDs?.contains(item.id) ?? (item.id == selectedID)
        return Button {
            select(item)
        } label: {
            HStack(spacing: 8 * uiScale) {
                Image(systemName: "checkmark")
                    .uiFont(.caption)
                    .frame(width: 12 * uiScale)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(label(item))
                    .uiFont(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .uiPadding(.horizontal, 8)
            .uiPadding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isHighlighted ? Color.white : Color.primary)
            .background(
                isHighlighted ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6 * uiScale)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(item))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(label(item))
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard !filteredItems.isEmpty else { return .ignored }
        let index = min(max(highlightedIndex + offset, 0), filteredItems.count - 1)
        highlightedID = filteredItems[index].id
        return .handled
    }

    private func chooseHighlighted() {
        guard filteredItems.indices.contains(highlightedIndex) else { return }
        select(filteredItems[highlightedIndex])
    }

    private func select(_ item: Item) {
        if !keepsOpenOnSelection { isPresented = false }
        choose(item)
        if keepsOpenOnSelection { isSearchFocused = true }
    }

    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard filteredItems.indices.contains(highlightedIndex) else { return }
        let id = filteredItems[highlightedIndex].id
        if reduceMotion {
            proxy.scrollTo(id)
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                proxy.scrollTo(id)
            }
        }
    }
}
