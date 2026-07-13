import AppKit
import SwiftUI

struct TranslationView: View {
    @ObservedObject var viewModel: TranslationViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSourceFocused: Bool
    @State private var panelWidth = TranslationPanelContentSizing.defaultWidth

    let openSettingsAction: () -> Void
    let openAccessibilitySettingsAction: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            sourceCard
            languageBar
            providerRow

            if shouldShowDetails {
                detailArea
                    .frame(height: detailAreaHeight)
                    .layoutPriority(1)
            }
        }
        .padding(9)
        .frame(
            minWidth: 360,
            maxWidth: .infinity,
            alignment: .top
        )
        .frame(height: panelHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(panelBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(panelBorder, lineWidth: 1)
        )
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updatePanelWidth(geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { newWidth in
                        updatePanelWidth(newWidth)
                    }
            }
        }
        .onChange(of: viewModel.focusRequestID) { _ in
            isSourceFocused = true
        }
        .onAppear {
            isSourceFocused = true
        }
        .onDisappear {
            viewModel.cancelTranslation()
        }
    }

    private var sourceCard: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(
                text: Binding(
                    get: { viewModel.inputText },
                    set: { viewModel.updateInputText($0) }
                )
            )
            .font(.system(size: 14))
            .focused($isSourceFocused)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.bottom, 17)
            .accessibilityLabel("原文")
            .accessibilityHint(
                viewModel.state == .translating
                    ? "按 Enter 停止翻译，按 Shift+Enter 插入换行"
                    : "按 Enter 翻译，按 Shift+Enter 插入换行"
            )

            if viewModel.inputText.isEmpty {
                Text("输入或粘贴需要翻译的文本")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if !viewModel.inputText.isEmpty {
                Text("\(viewModel.inputText.count) 个字符")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 12)
                    .padding(.bottom, 7)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: sourceCardHeight)
        .background(sourceBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(sourceBorder, lineWidth: isSourceFocused ? 1.5 : 0.5)
        )
    }

    private var languageBar: some View {
        HStack(spacing: 6) {
            sourceLanguageMenu

            Button(action: { viewModel.swapLanguages() }) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(
                        controlRowBackground,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(controlBorder, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .accessibilityLabel("交换翻译语言")
            .help("交换翻译语言")

            targetLanguageMenu
        }
        .frame(height: 30)
    }

    private var sourceLanguageMenu: some View {
        Menu {
            ForEach(TranslationLanguage.allCases) { language in
                if viewModel.sourceSelection == language {
                    Button(action: { viewModel.selectSourceLanguage(language) }) {
                        Label(language.displayName, systemImage: "checkmark")
                    }
                } else {
                    Button(language.displayName) {
                        viewModel.selectSourceLanguage(language)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(viewModel.sourceSelection.displayName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                controlRowBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(controlBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("来源语言")
        .accessibilityValue(Text(verbatim: viewModel.sourceSelection.displayName))
    }

    private var targetLanguageMenu: some View {
        Menu {
            if viewModel.targetSelection == .preferred {
                Button(action: { viewModel.selectTargetLanguage(.preferred) }) {
                    Label(TranslationTargetSelection.preferred.displayName, systemImage: "checkmark")
                }
            } else {
                Button(TranslationTargetSelection.preferred.displayName) {
                    viewModel.selectTargetLanguage(.preferred)
                }
            }

            Divider()

            ForEach(TranslationLanguage.targetLanguages) { language in
                let selection = TranslationTargetSelection.language(language)
                if viewModel.targetSelection == selection {
                    Button(action: { viewModel.selectTargetLanguage(selection) }) {
                        Label(language.displayName, systemImage: "checkmark")
                    }
                } else {
                    Button(language.displayName) {
                        viewModel.selectTargetLanguage(selection)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(viewModel.targetSelection.displayName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                controlRowBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(controlBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("目标语言")
        .accessibilityValue(Text(verbatim: viewModel.targetSelection.displayName))
    }

    private var providerRow: some View {
        HStack(spacing: 7) {
            providerMenu

            if viewModel.selectedProvider == .openAICompatible {
                Divider()
                    .frame(height: 12)

                Text(viewModel.settings.aiModel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }

            if let detectedLanguage = viewModel.detectedSourceLanguage {
                Divider()
                    .frame(height: 12)

                Text("识别为\(detectedLanguage.displayName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: openSettingsAction) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(
                detailBackground,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(controlBorder, lineWidth: 0.5)
            )
            .accessibilityLabel("打开翻译设置")
            .help("翻译设置")

            Button(action: primaryAction) {
                HStack(spacing: 5) {
                    Text(viewModel.state == .translating ? "停止" : "翻译")
                    Image(systemName: viewModel.state == .translating ? "stop.fill" : "arrow.right")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(primaryActionForeground)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    primaryActionBackground,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.state != .translating && !viewModel.canTranslate)
            .accessibilityLabel(viewModel.state == .translating ? "停止翻译" : "翻译")
            .help(
                viewModel.state == .translating
                    ? "按 Enter 停止翻译，按 Shift+Enter 插入换行"
                    : "按 Enter 翻译，按 Shift+Enter 插入换行"
            )
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(controlRowBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(controlBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var detailArea: some View {
        if let notice = viewModel.inlineNotice {
            noticeDetail(notice)
        } else if !viewModel.resultText.isEmpty {
            VStack(spacing: 6) {
                if let errorMessage = viewModel.errorMessage {
                    errorDetail(errorMessage)
                        .frame(height: errorDisplayHeight(errorMessage))
                }
                resultDetail
                    .frame(height: resultDisplayHeight)
            }
        } else if let errorMessage = viewModel.errorMessage {
            errorDetail(errorMessage)
        } else {
            loadingDetail
        }
    }

    private func noticeDetail(_ notice: TranslationInlineNotice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(notice.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            if notice == .accessibilityPermissionRequired {
                Button("打开系统设置", action: openAccessibilitySettingsAction)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 54, maxHeight: .infinity)
        .background(
            Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func errorDetail(_ errorMessage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            if viewModel.needsSettings {
                Button("打开设置", action: openSettingsAction)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 54, maxHeight: .infinity)
        .background(
            Color.red.opacity(colorScheme == .dark ? 0.15 : 0.07),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.red.opacity(0.16), lineWidth: 0.5)
        )
    }

    private var loadingDetail: some View {
        HStack(spacing: 8) {
            if viewModel.state == .translating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在翻译")
                Text("正在翻译…")
            } else {
                Text("暂无译文")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: .infinity)
        .background(detailBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(controlBorder, lineWidth: 0.5)
        )
    }

    private var resultDetail: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                Text(viewModel.resultText)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.leading, 12)
                    .padding(.trailing, viewModel.state == .translating ? 68 : 42)
                    .padding(.vertical, 10)
            }

            HStack(spacing: 3) {
                if viewModel.state == .translating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 28)
                        .accessibilityLabel("正在翻译")
                }

                Button(action: { viewModel.copyResult() }) {
                    Image(systemName: viewModel.didCopyResult ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    viewModel.didCopyResult ? Color.green : Color(nsColor: .secondaryLabelColor)
                )
                .background(
                    controlRowBackground,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(controlBorder, lineWidth: 0.5)
                )
                .accessibilityLabel(viewModel.didCopyResult ? "已复制" : "复制译文")
                .help(viewModel.didCopyResult ? "已复制" : "复制译文")
            }
            .padding(6)
        }
        .frame(minHeight: 54, maxHeight: .infinity)
        .background(detailBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(controlBorder, lineWidth: 0.5)
        )
    }

    private var providerMenu: some View {
        Menu {
            ForEach(TranslationProviderID.allCases) { provider in
                if viewModel.selectedProvider == provider {
                    Button(action: { viewModel.selectProvider(provider) }) {
                        Label(provider.displayName, systemImage: "checkmark")
                    }
                } else {
                    Button(provider.displayName) {
                        viewModel.selectProvider(provider)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: providerSymbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 16)
                Text("\(viewModel.selectedProvider.displayName) 翻译")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .accessibilityLabel("翻译服务")
        .accessibilityValue(Text(verbatim: viewModel.selectedProvider.displayName))
    }

    private var providerSymbolName: String {
        switch viewModel.selectedProvider {
        case .openAICompatible:
            return "sparkles"
        case .deepL:
            return "diamond.fill"
        }
    }

    private var shouldShowDetails: Bool {
        viewModel.state != .idle || viewModel.inlineNotice != nil
    }

    private var sourceCardHeight: CGFloat {
        TranslationPanelContentSizing.sourceHeight(
            text: viewModel.inputText,
            panelWidth: panelWidth
        )
    }

    private var detailAreaHeight: CGFloat {
        TranslationPanelContentSizing.detailHeight(
            state: viewModel.state,
            inlineNotice: viewModel.inlineNotice,
            errorMessage: viewModel.errorMessage,
            resultText: viewModel.resultText,
            panelWidth: panelWidth
        )
    }

    private var panelHeight: CGFloat {
        TranslationPanelContentSizing.panelHeight(
            state: viewModel.state,
            inlineNotice: viewModel.inlineNotice,
            errorMessage: viewModel.errorMessage,
            inputText: viewModel.inputText,
            resultText: viewModel.resultText,
            panelWidth: panelWidth
        )
    }

    private func errorDisplayHeight(_ message: String) -> CGFloat {
        TranslationPanelContentSizing.errorHeight(
            message: message,
            panelWidth: panelWidth
        )
    }

    private var resultDisplayHeight: CGFloat {
        guard
            !viewModel.resultText.isEmpty,
            let errorMessage = viewModel.errorMessage
        else {
            return detailAreaHeight
        }

        return max(54, detailAreaHeight - errorDisplayHeight(errorMessage) - 6)
    }

    private func updatePanelWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0, abs(panelWidth - width) > 0.5 else {
            return
        }
        panelWidth = width
    }

    private var panelBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private var sourceBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    private var controlRowBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var detailBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    private var controlBorder: Color {
        Color(nsColor: .separatorColor)
            .opacity(colorScheme == .dark ? 0.75 : 0.55)
    }

    private var sourceBorder: Color {
        isSourceFocused
            ? Color.accentColor.opacity(colorScheme == .dark ? 0.9 : 0.72)
            : controlBorder
    }

    private var panelBorder: Color {
        Color(nsColor: .separatorColor)
            .opacity(colorScheme == .dark ? 0.55 : 0.35)
    }

    private var primaryActionTint: Color {
        viewModel.state == .translating ? Color.red : Color.accentColor
    }

    private var canPerformPrimaryAction: Bool {
        viewModel.state == .translating || viewModel.canTranslate
    }

    private var primaryActionBackground: Color {
        canPerformPrimaryAction
            ? primaryActionTint.opacity(colorScheme == .dark ? 0.22 : 0.12)
            : Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04)
    }

    private var primaryActionForeground: Color {
        canPerformPrimaryAction
            ? primaryActionTint
            : Color(nsColor: .tertiaryLabelColor)
    }

    private func primaryAction() {
        if viewModel.state == .translating {
            viewModel.cancelTranslation()
        } else {
            viewModel.startTranslation()
        }
    }
}

@MainActor
enum TranslationPanelContentSizing {
    nonisolated static let defaultWidth: CGFloat = 390
    static let minimumPanelHeight: CGFloat = 176
    static let expandedMinimumPanelHeight: CGFloat = 232
    static let maximumPanelHeight: CGFloat = 522

    private static let sourceMinimumHeight: CGFloat = 76
    private static let sourceMaximumHeight: CGFloat = 160
    private static let resultMinimumHeight: CGFloat = 54
    private static let resultMaximumHeight: CGFloat = 220
    private static let detailMaximumHeight: CGFloat = 260
    private static let messageMaximumHeight: CGFloat = 110

    static func sourceHeight(text: String, panelWidth: CGFloat) -> CGFloat {
        let textWidth = max(1, panelWidth - 48)
        let contentHeight = measuredTextHeight(
            text,
            font: .systemFont(ofSize: 14),
            width: textWidth
        ) + 29
        return min(sourceMaximumHeight, max(sourceMinimumHeight, contentHeight))
    }

    static func errorHeight(message: String, panelWidth: CGFloat) -> CGFloat {
        let textWidth = max(1, panelWidth - 150)
        let contentHeight = measuredTextHeight(
            message,
            font: .systemFont(ofSize: 12),
            width: textWidth
        ) + 16
        return min(messageMaximumHeight, max(resultMinimumHeight, contentHeight))
    }

    static func detailHeight(
        state: TranslationViewState,
        inlineNotice: TranslationInlineNotice?,
        errorMessage: String?,
        resultText: String,
        panelWidth: CGFloat
    ) -> CGFloat {
        if let inlineNotice {
            return errorHeight(message: inlineNotice.message, panelWidth: panelWidth)
        }

        guard !resultText.isEmpty else {
            if let errorMessage {
                return errorHeight(message: errorMessage, panelWidth: panelWidth)
            }
            return resultMinimumHeight
        }

        let resultTextWidth = max(1, panelWidth - (state == .translating ? 98 : 72))
        let resultHeight = min(
            resultMaximumHeight,
            max(
                resultMinimumHeight,
                measuredTextHeight(
                    resultText,
                    font: .systemFont(ofSize: 14),
                    width: resultTextWidth
                ) + 20
            )
        )

        guard let errorMessage else {
            return resultHeight
        }

        return min(
            detailMaximumHeight,
            errorHeight(message: errorMessage, panelWidth: panelWidth) + 6 + resultHeight
        )
    }

    static func panelHeight(
        state: TranslationViewState,
        inlineNotice: TranslationInlineNotice?,
        errorMessage: String?,
        inputText: String,
        resultText: String,
        panelWidth: CGFloat
    ) -> CGFloat {
        let source = sourceHeight(text: inputText, panelWidth: panelWidth)
        let isExpanded = state != .idle || inlineNotice != nil

        guard isExpanded else {
            return max(minimumPanelHeight, source + 96)
        }

        let detail = detailHeight(
            state: state,
            inlineNotice: inlineNotice,
            errorMessage: errorMessage,
            resultText: resultText,
            panelWidth: panelWidth
        )
        return min(
            maximumPanelHeight,
            max(expandedMinimumPanelHeight, source + detail + 102)
        )
    }

    private static func measuredTextHeight(
        _ text: String,
        font: NSFont,
        width: CGFloat
    ) -> CGFloat {
        let measurableText: String
        if text.isEmpty {
            measurableText = " "
        } else if text.hasSuffix("\n") {
            measurableText = text + " "
        } else {
            measurableText = text
        }

        let bounds = (measurableText as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(bounds.height)
    }
}
