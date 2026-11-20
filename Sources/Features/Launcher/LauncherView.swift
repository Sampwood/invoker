import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherSearchViewModel
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @FocusState private var isSearchFocused: Bool
    @State private var lastPointerLocation: CGPoint?

    let executeAction: (LauncherSearchResult) -> Void

    var body: some View {
        let results = viewModel.results

        GlassEffectContainer(spacing: 0) {
            VStack(spacing: LauncherMetrics.surfaceSpacing) {
                glassSurface(searchField, in: Capsule())
                glassSurface(
                    resultsPanel(results),
                    in: RoundedRectangle(
                        cornerRadius: LauncherMetrics.cornerRadius,
                        style: .continuous
                    )
                )
            }
            .frame(
                width: LauncherMetrics.bodyWidth,
                height: LauncherMetrics.bodyHeight,
                alignment: .top
            )
        }
        .padding(LauncherMetrics.shadowPadding)
        .frame(
            width: LauncherMetrics.windowWidth,
            height: LauncherMetrics.windowHeight
        )
        .background(Color.clear)
        .onAppear {
            isSearchFocused = true
            lastPointerLocation = NSEvent.mouseLocation
            viewModel.reconcileSelection()
        }
        .onChange(of: viewModel.focusRequestID) {
            isSearchFocused = true
            lastPointerLocation = NSEvent.mouseLocation
        }
    }

    private func glassSurface<Content: View, Surface: Shape>(
        _ content: Content,
        in shape: Surface
    ) -> some View {
        Group {
            if accessibilityReduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        }
        .clipShape(shape)
        .overlay {
            if colorSchemeContrast == .increased {
                shape.stroke(Color.primary.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .shadow(
            color: .black.opacity(0.12),
            radius: LauncherMetrics.shadowRadius,
            y: LauncherMetrics.shadowYOffset
        )
    }

    private func resultsPanel(_ results: [LauncherSearchResult]) -> some View {
        VStack(spacing: 0) {
            if viewModel.isScanning && !results.isEmpty {
                Text("正在查找应用…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(height: LauncherMetrics.scanStatusHeight)
            }
            commandList(results)
        }
        .frame(
            width: LauncherMetrics.bodyWidth,
            height: LauncherMetrics.resultsHeight,
            alignment: .top
        )
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .accessibilityHidden(true)

            TextField("搜索命令或应用", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($isSearchFocused)
                .accessibilityAddTraits(.isSearchField)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, LauncherMetrics.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: LauncherMetrics.searchHeight)
    }

    @ViewBuilder
    private func commandList(_ results: [LauncherSearchResult]) -> some View {
        if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .accessibilityHidden(true)
                Text(viewModel.isScanning ? "正在查找应用…" : "没有匹配的命令或应用")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: LauncherMetrics.rowSpacing) {
                        ForEach(results) { command in
                            commandRow(command)
                                .id(command.id)
                        }
                    }
                    .padding(.vertical, LauncherMetrics.listVerticalPadding)
                    .padding(.horizontal, LauncherMetrics.listHorizontalPadding)
                }
                .onChange(of: viewModel.scrollRequestID) {
                    guard let selectedID = viewModel.selectedCommandID else { return }
                    lastPointerLocation = NSEvent.mouseLocation
                    withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12)) {
                        proxy.scrollTo(selectedID)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultIcon(_ result: LauncherSearchResult) -> some View {
        if case .application(let application) = result {
            Image(nsImage: LauncherIconCache.shared.image(for: application))
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: result.systemImage)
        }
    }

    private func commandRow(_ command: LauncherSearchResult) -> some View {
        let isSelected = viewModel.selectedCommandID == command.id
        let shape = RoundedRectangle(
            cornerRadius: LauncherMetrics.rowCornerRadius,
            style: .continuous
        )
        let hasStrongOutline = colorSchemeContrast == .increased || differentiateWithoutColor

        return Button {
            executeAction(command)
        } label: {
            HStack(spacing: 12) {
                resultIcon(command)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color(nsColor: .secondaryLabelColor)
                    )
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(1)

                    if !command.subtitle.isEmpty {
                        Text(command.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Color.primary.opacity(accessibilityReduceTransparency ? 0.08 : 0.04),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    Color.primary.opacity(colorSchemeContrast == .increased ? 0.5 : 0.12),
                                    lineWidth: 1
                                )
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: LauncherMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(
                        Color.accentColor.opacity(
                            isSelected ? (colorSchemeContrast == .increased ? 0.2 : 0.1) : 0
                        )
                    )
                    .overlay {
                        shape.stroke(
                            (differentiateWithoutColor ? Color.primary : Color.accentColor)
                                .opacity(isSelected ? (hasStrongOutline ? 0.75 : 0.35) : 0),
                            lineWidth: hasStrongOutline ? 1.5 : 1
                        )
                    }
                    .animation(
                        accessibilityReduceMotion ? nil : .easeOut(duration: 0.12),
                        value: isSelected
                    )
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            let location = NSEvent.mouseLocation
            // Scrolling under a stationary pointer must not replace the keyboard selection.
            guard location != lastPointerLocation else { return }
            lastPointerLocation = location
            viewModel.select(command)
        }
    }
}

enum LauncherMetrics {
    static let bodyWidth: CGFloat = 680
    static let bodyHeight: CGFloat = 430
    static let cornerRadius: CGFloat = 24
    static let searchHeight: CGFloat = 64
    static let surfaceSpacing: CGFloat = 8
    static let resultsHeight: CGFloat = bodyHeight - searchHeight - surfaceSpacing
    static let scanStatusHeight: CGFloat = 24
    static let rowHeight: CGFloat = 58
    static let rowSpacing: CGFloat = 4
    static let rowCornerRadius: CGFloat = rowHeight / 2
    static let horizontalPadding: CGFloat = 20
    static let listHorizontalPadding: CGFloat = 10
    static let listVerticalPadding: CGFloat = 10
    static let shadowPadding: CGFloat = 20
    static let shadowRadius: CGFloat = 11
    static let shadowYOffset: CGFloat = 4
    static let windowWidth: CGFloat = bodyWidth + shadowPadding * 2
    static let windowHeight: CGFloat = bodyHeight + shadowPadding * 2
}
