import AppKit
import SwiftUI

@MainActor
final class ClipboardHistoryPresentationState: ObservableObject {
    @Published var query = ""
    @Published private(set) var selectedItemID: ClipboardHistoryItem.ID?
    @Published private(set) var focusRequestID = UUID()

    func prepare(for items: [ClipboardHistoryItem]) {
        query = ""
        selectedItemID = items.first?.id
    }

    func requestSearchFocus() {
        focusRequestID = UUID()
    }

    func filteredItems(from items: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
            let searchableText: String
            switch item.kind {
            case .text:
                searchableText = (item.text ?? "") + " 文本"
            case .image:
                searchableText = "图片"
            }
            return searchableText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func selectedItem(from items: [ClipboardHistoryItem]) -> ClipboardHistoryItem? {
        guard let selectedItemID else {
            return nil
        }
        return filteredItems(from: items).first { $0.id == selectedItemID }
    }

    func select(_ item: ClipboardHistoryItem) {
        selectedItemID = item.id
    }

    func selectFirstMatch(in items: [ClipboardHistoryItem]) {
        selectedItemID = filteredItems(from: items).first?.id
    }

    func reconcileSelection(in items: [ClipboardHistoryItem]) {
        let filteredItems = filteredItems(from: items)
        guard !filteredItems.isEmpty else {
            selectedItemID = nil
            return
        }

        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = filteredItems.first?.id
    }

    func moveSelection(by offset: Int, in items: [ClipboardHistoryItem]) {
        let filteredItems = filteredItems(from: items)
        guard !filteredItems.isEmpty else {
            selectedItemID = nil
            return
        }

        guard let selectedItemID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID })
        else {
            self.selectedItemID = filteredItems.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        self.selectedItemID = filteredItems[nextIndex].id
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @ObservedObject var presentationState: ClipboardHistoryPresentationState
    @FocusState private var isSearchFocused: Bool

    let applyAction: (ClipboardHistoryItem) -> Void
    let clearAction: () -> Void

    private var filteredItems: [ClipboardHistoryItem] {
        presentationState.filteredItems(from: store.items)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bodyShadow
            panelBody
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

    private var bodyShadow: some View {
        RoundedRectangle(cornerRadius: ClipboardHistoryMetrics.bodyCornerRadius, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(width: ClipboardHistoryMetrics.bodyWidth, height: ClipboardHistoryMetrics.bodyHeight)
            .shadow(
                color: .black.opacity(ClipboardHistoryMetrics.shadowOpacity),
                radius: ClipboardHistoryMetrics.shadowRadius,
                x: 0,
                y: ClipboardHistoryMetrics.shadowYOffset
            )
    }

    private var panelBody: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: ClipboardHistoryMetrics.bodyWidth, height: ClipboardHistoryMetrics.bodyHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: ClipboardHistoryMetrics.bodyCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ClipboardHistoryMetrics.bodyCornerRadius, style: .continuous)
                .stroke(
                    Color.black.opacity(ClipboardHistoryMetrics.bodyBorderOpacity),
                    lineWidth: ClipboardHistoryMetrics.bodyBorderLineWidth
                )
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("剪贴板历史")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text(countText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer(minLength: 12)
            searchField
            Spacer(minLength: 12)

            Button(action: clearAction) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        store.items.isEmpty
                            ? Color(nsColor: .tertiaryLabelColor)
                            : Color(nsColor: .secondaryLabelColor)
                    )
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(store.items.isEmpty ? 0 : 0.06))
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty)
            .help("清空历史")
            .accessibilityLabel("清空剪贴板历史")
        }
        .frame(height: ClipboardHistoryMetrics.headerHeight, alignment: .center)
        .padding(.horizontal, ClipboardHistoryMetrics.horizontalPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(height: 1)
        }
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
        .padding(.horizontal, 9)
        .frame(width: ClipboardHistoryMetrics.searchWidth, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        )
    }

    private var countText: String {
        if store.items.isEmpty {
            return "暂无记录"
        }
        if !presentationState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "找到 " + String(filteredItems.count) + " 条"
        }
        return "最近 " + String(store.items.count) + " 条"
    }

    private var content: some View {
        HStack(spacing: 0) {
            historyList
                .frame(width: ClipboardHistoryMetrics.listWidth)

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var historyList: some View {
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
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            ClipboardHistoryRow(
                                item: item,
                                isSelected: presentationState.selectedItemID == item.id,
                                selectAction: {
                                    presentationState.select(item)
                                },
                                applyAction: {
                                    applyAction(item)
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, ClipboardHistoryMetrics.listVerticalPadding)
                    .background(ClipboardHistoryScrollViewConfiguration())
                }
                .scrollIndicators(.automatic)
                .onChange(of: presentationState.selectedItemID) { selectedItemID in
                    guard let selectedItemID else {
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
    private var detailPane: some View {
        if let item = presentationState.selectedItem(from: store.items) {
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
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
    }
}

private struct ClipboardHistoryDetailView: View {
    let item: ClipboardHistoryItem
    let applyAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(ClipboardHistoryFormatting.formattedDate(item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .monospacedDigit()

                Spacer(minLength: 0)

                Button(action: applyAction) {
                    Label("粘贴", systemImage: "arrow.turn.down.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("粘贴到原前台应用")
            }
            .frame(height: ClipboardHistoryMetrics.detailHeaderHeight)
            .padding(.horizontal, 14)
            .background(Color(nsColor: .controlBackgroundColor))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(height: 1)

            detailContent
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var detailContent: some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
                    .background(ClipboardHistoryScrollViewConfiguration())
            }
            .scrollIndicators(.automatic)
        case .image:
            if let data = item.imagePNGData,
               let image = NSImage(data: data) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                }
                .padding(18)
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
}

private struct ClipboardHistoryRow: View {
    @State private var isHovered = false

    let item: ClipboardHistoryItem
    let isSelected: Bool
    let selectAction: () -> Void
    let applyAction: () -> Void

    var body: some View {
        Button(action: selectAction) {
            HStack(spacing: 10) {
                if item.kind == .image {
                    thumbnail
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(ClipboardHistoryFormatting.title(for: item))
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(item.kind == .text ? 2 : 1)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .frame(
                width: ClipboardHistoryMetrics.listWidth
                    - ClipboardHistoryMetrics.rowOuterInset * 2
                    - ClipboardHistoryMetrics.rowHorizontalPadding * 2,
                height: ClipboardHistoryMetrics.rowHeight,
                alignment: .leading
            )
            .padding(.horizontal, ClipboardHistoryMetrics.rowHorizontalPadding)
            .background(rowBackground)
            .padding(.horizontal, ClipboardHistoryMetrics.rowOuterInset)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.45))
                    .frame(height: 1)
                    .padding(
                        .horizontal,
                        ClipboardHistoryMetrics.rowOuterInset + ClipboardHistoryMetrics.rowHorizontalPadding
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    applyAction()
                }
        )
        .onHover { isHovered = $0 }
        .accessibilityLabel(ClipboardHistoryFormatting.accessibilityTitle(for: item))
        .accessibilityHint("单击预览，双击粘贴")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: ClipboardHistoryMetrics.rowCornerRadius, style: .continuous)
            .fill(
                isSelected
                    ? Color(nsColor: .controlAccentColor).opacity(0.14)
                    : Color.black.opacity(isHovered ? 0.04 : 0)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(nsColor: .controlAccentColor))
                        .frame(width: 3, height: 22)
                        .padding(.leading, 2)
                }
            }
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
        case .text:
            return item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .image:
            return imageDimensions(from: item.imagePNGData) ?? "尺寸未知"
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
        case .text:
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

private struct ClipboardHistoryScrollViewConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> ClipboardHistoryScrollConfigurationView {
        ClipboardHistoryScrollConfigurationView()
    }

    func updateNSView(_ nsView: ClipboardHistoryScrollConfigurationView, context: Context) {
        nsView.configureEnclosingScrollView()
    }
}

private final class ClipboardHistoryScrollConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.controlSize = .small
                scrollView.tile()
                return
            }
            candidate = view.superview
        }
    }
}

enum ClipboardHistoryMetrics {
    static let bodyWidth: CGFloat = 740
    static let bodyHeight: CGFloat = 500
    static let headerHeight: CGFloat = 62
    static let detailHeaderHeight: CGFloat = 48
    static let listWidth: CGFloat = 330
    static let searchWidth: CGFloat = 280
    static let horizontalPadding: CGFloat = 16
    static let listVerticalPadding: CGFloat = 3
    static let rowHeight: CGFloat = 48
    static let rowOuterInset: CGFloat = 5
    static let rowHorizontalPadding: CGFloat = 10
    static let rowCornerRadius: CGFloat = 6
    static let thumbnailWidth: CGFloat = 40
    static let thumbnailHeight: CGFloat = 30
    static let shadowPadding: CGFloat = 20
    static let shadowOpacity: Double = 0.16
    static let shadowRadius: CGFloat = 14
    static let shadowYOffset: CGFloat = 2
    static let bodyCornerRadius: CGFloat = 10
    static let bodyBorderOpacity: Double = 0.22
    static let bodyBorderLineWidth: CGFloat = CalendarPopoverMetrics.bodyBorderLineWidth
    static let windowWidth: CGFloat = bodyWidth + shadowPadding * 2
    static let windowHeight: CGFloat = bodyHeight + shadowPadding * 2
}
