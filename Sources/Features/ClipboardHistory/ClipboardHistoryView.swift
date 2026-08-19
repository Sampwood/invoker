import AppKit
import SwiftUI

@MainActor
final class ClipboardHistoryPresentationState: ObservableObject {
    @Published var query = ""
    @Published private(set) var selectedItemID: ClipboardHistoryItem.ID?
    @Published private(set) var focusRequestID = UUID()

    func prepare(for items: [ClipboardHistoryItem]) {
        query = ""
        updateSelection(items.first?.id)
    }

    func requestSearchFocus() {
        focusRequestID = UUID()
    }

    func filteredItems(from items: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter {
            $0.searchableText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func selectedItem(from items: [ClipboardHistoryItem]) -> ClipboardHistoryItem? {
        guard let selectedItemID else {
            return nil
        }
        return filteredItems(from: items).first { $0.id == selectedItemID }
    }

    func select(_ item: ClipboardHistoryItem) {
        updateSelection(item.id)
    }

    func selectFirstMatch(in items: [ClipboardHistoryItem]) {
        updateSelection(filteredItems(from: items).first?.id)
    }

    func reconcileSelection(in items: [ClipboardHistoryItem]) {
        let filteredItems = filteredItems(from: items)
        guard !filteredItems.isEmpty else {
            updateSelection(nil)
            return
        }

        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        updateSelection(filteredItems.first?.id)
    }

    func moveSelection(by offset: Int, in items: [ClipboardHistoryItem]) {
        let filteredItems = filteredItems(from: items)
        guard !filteredItems.isEmpty else {
            updateSelection(nil)
            return
        }

        guard let selectedItemID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID })
        else {
            updateSelection(filteredItems.first?.id)
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        updateSelection(filteredItems[nextIndex].id)
    }

    private func updateSelection(_ itemID: ClipboardHistoryItem.ID?) {
        guard selectedItemID != itemID else {
            return
        }
        selectedItemID = itemID
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var presentationState: ClipboardHistoryPresentationState
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var isSearchFocused: Bool

    let applyAction: (ClipboardHistoryItem) -> Void
    let clearAction: () -> Void

    var body: some View {
        let filteredItems = presentationState.filteredItems(from: store.items)

        ZStack(alignment: .topLeading) {
            panelBody(filteredItems: filteredItems)
        }
        .offset(x: ClipboardHistoryMetrics.shadowPadding, y: ClipboardHistoryMetrics.shadowPadding)
        .frame(
            width: ClipboardHistoryMetrics.windowWidth,
            height: ClipboardHistoryMetrics.windowHeight,
            alignment: .topLeading
        )
        .background(Color.clear)
        .onAppear {
            presentationState.reconcileSelection(in: store.items)
            isSearchFocused = true
        }
        .onChange(of: presentationState.query) { _ in
            presentationState.selectFirstMatch(in: store.items)
        }
        .onChange(of: store.items) { items in
            presentationState.reconcileSelection(in: items)
        }
        .onChange(of: presentationState.focusRequestID) { _ in
            isSearchFocused = true
        }
    }

    private func panelBody(filteredItems: [ClipboardHistoryItem]) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: ClipboardHistoryMetrics.bodyCornerRadius,
            style: .continuous
        )
        let panel = VStack(spacing: 0) {
            header(filteredItemCount: filteredItems.count)
            content(filteredItems: filteredItems)
        }
        .frame(width: ClipboardHistoryMetrics.bodyWidth, height: ClipboardHistoryMetrics.bodyHeight)

        return Group {
            if accessibilityReduceTransparency {
                panel.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else {
                panel.glassEffect(.regular, in: shape)
            }
        }
        .clipShape(shape)
        .shadow(
            color: .black.opacity(ClipboardHistoryMetrics.shadowOpacity),
            radius: ClipboardHistoryMetrics.shadowRadius,
            y: ClipboardHistoryMetrics.shadowYOffset
        )
    }

    private func header(filteredItemCount: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("剪贴板历史")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text(countText(filteredItemCount: filteredItemCount))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer(minLength: 16)
            searchField

            Menu {
                Button(role: .destructive, action: clearAction) {
                    Label("清空未置顶历史", systemImage: "trash")
                }
                .disabled(!store.hasUnpinnedItems)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
            .accessibilityLabel("更多剪贴板历史操作")
        }
        .frame(height: ClipboardHistoryMetrics.headerHeight, alignment: .center)
        .padding(.horizontal, ClipboardHistoryMetrics.horizontalPadding)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            TextField("搜索剪贴板内容", text: $presentationState.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)

            if !presentationState.query.isEmpty {
                Button {
                    presentationState.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: ClipboardHistoryMetrics.searchWidth, height: ClipboardHistoryMetrics.searchHeight)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: separatorWidth))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSearchField)
    }

    private func countText(filteredItemCount: Int) -> String {
        if store.items.isEmpty {
            return "暂无记录"
        }
        if !presentationState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "找到 " + String(filteredItemCount) + " 条"
        }
        if store.pinnedItemCount == 0 {
            return "最近 " + String(store.unpinnedItemCount) + " 条"
        }
        if store.unpinnedItemCount == 0 {
            return String(store.pinnedItemCount) + " 条置顶"
        }
        return String(store.pinnedItemCount)
            + " 条置顶 · "
            + String(store.unpinnedItemCount)
            + " 条最近记录"
    }

    private func content(filteredItems: [ClipboardHistoryItem]) -> some View {
        HStack(spacing: 0) {
            historyList(filteredItems: filteredItems)
                .frame(width: ClipboardHistoryMetrics.listWidth)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(separatorOpacity))
                .frame(width: separatorWidth)

            detailPane(filteredItems: filteredItems)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func historyList(filteredItems: [ClipboardHistoryItem]) -> some View {
        if filteredItems.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: store.items.isEmpty ? "rectangle.on.rectangle" : "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                Text(store.items.isEmpty ? "暂无剪贴板历史" : "没有匹配结果")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ClipboardHistoryMetrics.rowSpacing) {
                        ForEach(filteredItems.indices, id: \.self) { index in
                            let item = filteredItems[index]

                            if index == 0 || filteredItems[index - 1].isPinned != item.isPinned {
                                Text(item.isPinned ? "置顶" : "最近")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                    .padding(.horizontal, 8)
                                    .padding(.top, index == 0 ? 3 : 8)
                                    .padding(.bottom, 2)
                            }

                            ClipboardHistoryRow(
                                item: item,
                                isSelected: presentationState.selectedItemID == item.id,
                                selectAction: {
                                    presentationState.select(item)
                                },
                                applyAction: {
                                    applyAction(item)
                                },
                                pinAction: {
                                    store.togglePin(for: item.id)
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.leading, ClipboardHistoryMetrics.listLeadingInset)
                    .padding(.trailing, ClipboardHistoryMetrics.listTrailingInset)
                    .padding(.vertical, ClipboardHistoryMetrics.listVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
                .clipboardHistoryScrollIndicatorInset(
                    ClipboardHistoryMetrics.scrollerTrailingInset
                )
                .onChange(of: presentationState.selectedItemID) { selectedItemID in
                    guard let selectedItemID else {
                        return
                    }
                    guard !accessibilityReduceMotion else {
                        proxy.scrollTo(selectedItemID, anchor: .center)
                        return
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selectedItemID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailPane(filteredItems: [ClipboardHistoryItem]) -> some View {
        if let selectedItemID = presentationState.selectedItemID,
           let item = filteredItems.first(where: { $0.id == selectedItemID }) {
            ClipboardHistoryDetailView(item: item) {
                applyAction(item)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                Text("选择一条记录查看详情")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var separatorWidth: CGFloat {
        colorSchemeContrast == .increased || differentiateWithoutColor ? 1.5 : 1
    }

    private var separatorOpacity: Double {
        colorSchemeContrast == .increased ? 0.9 : 0.58
    }

}

private struct ClipboardHistoryDetailView: View {
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let item: ClipboardHistoryItem
    let applyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: ClipboardHistoryFormatting.systemImage(for: item))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .frame(width: 30, height: 30)
                    .background(
                        Color(nsColor: .controlAccentColor).opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(ClipboardHistoryFormatting.kindTitle(for: item))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))

                    HStack(spacing: 5) {
                        if let sourceApplication = item.sourceApplication {
                            ClipboardSourceApplicationLabel(application: sourceApplication)

                            Text("·")
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }

                        Text(ClipboardHistoryFormatting.formattedDate(item.createdAt))
                            .monospacedDigit()
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                Spacer(minLength: 0)

                Button(action: applyAction) {
                    Label("粘贴", systemImage: "clipboard")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .help("粘贴到原前台应用")
                .accessibilityLabel("粘贴到原前台应用")
            }
            .frame(height: ClipboardHistoryMetrics.detailHeaderHeight)
            .padding(.horizontal, 18)

            Rectangle()
                .fill(
                    Color(nsColor: .separatorColor)
                        .opacity(colorSchemeContrast == .increased ? 0.9 : 0.58)
                )
                .frame(height: colorSchemeContrast == .increased ? 1.5 : 1)

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(contentBackground)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch item.kind {
        case .text, .richText, .file, .url:
            ScrollView {
                Text(ClipboardHistoryFormatting.detailText(for: item))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
            }
            .scrollIndicators(.automatic)
            .clipboardHistoryScrollIndicatorInset(
                ClipboardHistoryMetrics.scrollerTrailingInset
            )
        case .image:
            if let data = item.imagePNGData,
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

                    Text("无法预览图片")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var contentBackground: Color {
        Color(nsColor: .windowBackgroundColor)
            .opacity(accessibilityReduceTransparency ? 1 : 0.12)
    }
}

private struct ClipboardHistoryRow: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isHovered = false
    @State private var isPinHovered = false
    @State private var isPinLimitPresented = false
    @FocusState private var isPinFocused: Bool

    let item: ClipboardHistoryItem
    let isSelected: Bool
    let selectAction: () -> Void
    let applyAction: () -> Void
    let pinAction: () -> ClipboardPinToggleResult

    var body: some View {
        HStack(spacing: ClipboardHistoryMetrics.pinSpacing) {
            Button(action: selectAction) {
                HStack(spacing: 10) {
                    if item.kind == .image {
                        thumbnail
                    } else {
                        typeIcon
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ClipboardHistoryFormatting.title(for: item))
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 4) {
                            if let sourceApplication = item.sourceApplication {
                                Text(sourceApplication.name)
                                    .lineLimit(1)

                                Text("·")
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }

                            Text(ClipboardHistoryFormatting.formattedDate(item.createdAt))
                                .monospacedDigit()
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        applyAction()
                    }
            )
            .accessibilityLabel(ClipboardHistoryFormatting.accessibilityTitle(for: item))
            .accessibilityHint("单击预览，双击粘贴")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            pinButton
        }
        .padding(.leading, ClipboardHistoryMetrics.rowLeadingPadding)
        .padding(.trailing, ClipboardHistoryMetrics.rowTrailingPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: ClipboardHistoryMetrics.rowHeight,
            maxHeight: ClipboardHistoryMetrics.rowHeight,
            alignment: .leading
        )
        .background(rowBackground)
        .onHover { isHovered = $0 }
    }

    private var pinButton: some View {
        Button(action: togglePin) {
            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    item.isPinned
                        ? Color(nsColor: .controlAccentColor)
                        : Color(nsColor: .secondaryLabelColor)
                )
                .opacity(isPinVisible ? 1 : 0)
                .frame(
                    width: ClipboardHistoryMetrics.pinButtonSize,
                    height: ClipboardHistoryMetrics.pinButtonSize
                )
                .background(
                    Circle()
                        .fill(
                            Color.primary.opacity(isPinHovered && isPinVisible ? 0.07 : 0)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            Color(nsColor: .controlAccentColor).opacity(isPinFocused ? 0.85 : 0),
                            lineWidth: 1.5
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isPinFocused)
        .onHover { isPinHovered = $0 }
        .help(item.isPinned ? "取消置顶" : "置顶")
        .accessibilityLabel(pinAccessibilityLabel)
        .accessibilityValue(item.isPinned ? "已置顶" : "未置顶")
        .popover(isPresented: $isPinLimitPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("置顶已满")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text("最多可置顶 50 条，请先取消一项。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .padding(12)
            .frame(width: 210, alignment: .leading)
        }
    }

    private var isPinVisible: Bool {
        item.isPinned || isHovered || isSelected || isPinFocused
    }

    private var pinAccessibilityLabel: String {
        let action = item.isPinned ? "取消置顶" : "置顶"
        return action + "“" + ClipboardHistoryFormatting.accessibilityTitle(for: item) + "”"
    }

    private func togglePin() {
        let result: ClipboardPinToggleResult
        if accessibilityReduceMotion {
            result = pinAction()
        } else {
            var animatedResult = ClipboardPinToggleResult.limitReached
            withAnimation(.easeOut(duration: 0.14)) {
                animatedResult = pinAction()
            }
            result = animatedResult
        }

        guard result == .limitReached else {
            return
        }

        isPinLimitPresented = true
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "置顶已满，最多可置顶 50 条。",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: ClipboardHistoryMetrics.rowCornerRadius, style: .continuous)
            .fill(
                isSelected
                    ? Color(nsColor: .controlAccentColor).opacity(
                        colorSchemeContrast == .increased ? 0.20 : 0.12
                    )
                    : Color.primary.opacity(isHovered ? 0.055 : 0)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClipboardHistoryMetrics.rowCornerRadius,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: .controlAccentColor).opacity(
                        isSelected ? (colorSchemeContrast == .increased ? 0.72 : 0.34) : 0
                    ),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Color(nsColor: .controlAccentColor))
                        .frame(width: differentiateWithoutColor ? 3 : 2, height: 24)
                        .padding(.leading, 3)
                }
            }
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.14),
                value: isSelected
            )
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovered
            )
    }

    private var typeIcon: some View {
        Image(systemName: ClipboardHistoryFormatting.systemImage(for: item))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(nsColor: .controlAccentColor))
            .frame(width: 28, height: 28)
            .background(
                Color(nsColor: .controlAccentColor).opacity(0.10),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.imagePNGData,
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: ClipboardHistoryMetrics.thumbnailWidth,
                    height: ClipboardHistoryMetrics.thumbnailHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                )
                .frame(
                    width: ClipboardHistoryMetrics.thumbnailWidth,
                    height: ClipboardHistoryMetrics.thumbnailHeight
                )
        }
    }
}

private enum ClipboardHistoryFormatting {
    static func title(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .text, .richText, .file, .url:
            return item.displayTitle
        case .image:
            return imageDimensions(from: item.imagePNGData) ?? "尺寸未知"
        }
    }

    static func detailText(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .file:
            let files = item.snapshot.urls
            return files.isEmpty ? item.displayTitle : files.joined(separator: "\n")
        case .url:
            return item.snapshot.urls.joined(separator: "\n")
        case .richText, .text:
            return item.text ?? ""
        case .image:
            return item.ocrText ?? ""
        }
    }

    static func kindTitle(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .text: return "文本"
        case .richText: return "富文本"
        case .image: return "图片"
        case .file: return "文件"
        case .url: return "链接"
        }
    }

    static func systemImage(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        }
    }

    static func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 " + timeFormatter.string(from: date)
        }
        return dateFormatter.string(from: date)
    }

    static func accessibilityTitle(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .text, .richText, .file, .url:
            return title(for: item)
        case .image:
            return "图片，" + title(for: item)
        }
    }

    private static func imageDimensions(from data: Data?) -> String? {
        guard let data,
              let representation = NSBitmapImageRep(data: data)
        else {
            return nil
        }
        return String(representation.pixelsWide) + " × " + String(representation.pixelsHigh)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

private struct ClipboardSourceApplicationLabel: View {
    let application: ClipboardSourceApplication

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
            }

            Text(application.name)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .lineLimit(1)
        }
    }

    private var icon: NSImage? {
        guard let bundlePath = application.bundlePath else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundlePath)
    }
}

private extension View {
    func clipboardHistoryScrollIndicatorInset(_ inset: CGFloat) -> some View {
        contentMargins(.trailing, inset, for: .scrollIndicators)
    }
}

enum ClipboardHistoryMetrics {
    static let bodyWidth: CGFloat = 780
    static let bodyHeight: CGFloat = 520
    static let headerHeight: CGFloat = 64
    static let detailHeaderHeight: CGFloat = 60
    static let listWidth: CGFloat = 276
    static let searchWidth: CGFloat = 240
    static let searchHeight: CGFloat = 32
    static let horizontalPadding: CGFloat = 18
    static let listVerticalPadding: CGFloat = 10
    static let rowHeight: CGFloat = 52
    static let rowSpacing: CGFloat = 2
    static let listLeadingInset: CGFloat = 10
    static let listTrailingInset: CGFloat = 12
    static let scrollerTrailingInset: CGFloat = 2
    static let rowLeadingPadding: CGFloat = 12
    static let rowTrailingPadding: CGFloat = 4
    static let rowCornerRadius: CGFloat = 8
    static let pinButtonSize: CGFloat = 26
    static let pinSpacing: CGFloat = 6
    static let thumbnailWidth: CGFloat = 40
    static let thumbnailHeight: CGFloat = 30
    static let shadowPadding: CGFloat = 20
    static let shadowOpacity: Double = 0.12
    static let shadowRadius: CGFloat = 11
    static let shadowYOffset: CGFloat = 4
    static let bodyCornerRadius: CGFloat = 18
    static let windowWidth: CGFloat = bodyWidth + shadowPadding * 2
    static let windowHeight: CGFloat = bodyHeight + shadowPadding * 2
}
