import SwiftUI

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherSearchViewModel
    @FocusState private var isSearchFocused: Bool

    let executeAction: (LauncherCommand) -> Void

    var body: some View {
        let results = viewModel.results

        VStack(spacing: 0) {
            searchField
            Divider()
                .opacity(0.55)
            commandList(results)
        }
        .frame(
            width: LauncherMetrics.width,
            height: LauncherMetrics.height,
            alignment: .top
        )
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: LauncherMetrics.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: LauncherMetrics.cornerRadius,
                style: .continuous
            )
            .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .onAppear {
            isSearchFocused = true
            viewModel.reconcileSelection()
        }
        .onChange(of: viewModel.query) {
            viewModel.selectFirstMatch()
        }
        .onChange(of: viewModel.focusRequestID) {
            isSearchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            TextField("搜索命令", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($isSearchFocused)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
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
        .frame(height: LauncherMetrics.searchHeight)
    }

    @ViewBuilder
    private func commandList(_ results: [LauncherCommand]) -> some View {
        if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                Text("没有匹配的命令")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { command in
                            commandRow(command)
                                .id(command.id)
                        }
                    }
                    .padding(.vertical, LauncherMetrics.listVerticalPadding)
                    .padding(.horizontal, LauncherMetrics.listHorizontalPadding)
                }
                .onChange(of: viewModel.selectedCommandID) { _, selectedID in
                    guard let selectedID else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private func commandRow(_ command: LauncherCommand) -> some View {
        let isSelected = viewModel.selectedCommandID == command.id

        return Button {
            executeAction(command)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: command.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        isSelected
                            ? Color.white
                            : Color(nsColor: .secondaryLabelColor)
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        (isSelected
                            ? Color.accentColor
                            : Color(nsColor: .controlBackgroundColor))
                        .opacity(isSelected ? 1 : 0.85),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : Color(nsColor: .labelColor)
                        )
                        .lineLimit(1)

                    Text(command.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            isSelected
                                ? Color.white.opacity(0.78)
                                : Color(nsColor: .secondaryLabelColor)
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            isSelected
                                ? Color.white.opacity(0.78)
                                : Color(nsColor: .secondaryLabelColor)
                        )
                }
            }
            .padding(.horizontal, 12)
            .frame(height: LauncherMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isSelected
                    ? Color.accentColor
                    : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                viewModel.select(command)
            }
        }
    }
}

enum LauncherMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 430
    static let cornerRadius: CGFloat = 16
    static let searchHeight: CGFloat = 72
    static let rowHeight: CGFloat = 58
    static let horizontalPadding: CGFloat = 20
    static let listHorizontalPadding: CGFloat = 10
    static let listVerticalPadding: CGFloat = 10
}
