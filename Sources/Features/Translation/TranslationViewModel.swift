import AppKit
import Combine
import Foundation

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published private(set) var inputText = ""
    @Published private(set) var sourceSelection = TranslationLanguage.automatic
    @Published private(set) var targetSelection = TranslationTargetSelection.preferred
    @Published private(set) var providerOutputs: [TranslationProviderID: TranslationProviderOutput]
    @Published private(set) var state = TranslationViewState.idle
    @Published private(set) var detectedSourceLanguage: TranslationLanguage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var inlineNotice: TranslationInlineNotice?
    @Published private(set) var needsSettings = false
    @Published private(set) var focusRequestID = UUID()
    @Published private(set) var activeAIModel: String

    let settings: TranslationSettingsStore

    private let providerRegistry: TranslationProviderResolving
    private let languageResolver: TranslationLanguageResolver
    private var translationTasks: [TranslationProviderID: Task<Void, Never>] = [:]
    private var copyFeedbackTasks: [TranslationProviderID: Task<Void, Never>] = [:]
    private var activeRequestID: UUID?

    init(
        settings: TranslationSettingsStore,
        providerRegistry: TranslationProviderResolving,
        languageResolver: TranslationLanguageResolver = TranslationLanguageResolver()
    ) {
        self.settings = settings
        self.providerRegistry = providerRegistry
        self.languageResolver = languageResolver
        activeAIModel = settings.effectiveAIModel
        providerOutputs = Self.emptyProviderOutputs(aiModel: settings.effectiveAIModel)
    }

    var canTranslate: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resultText: String {
        providerOutputs[settings.activeProvider]?.text ?? ""
    }

    func output(for provider: TranslationProviderID) -> TranslationProviderOutput {
        providerOutputs[provider] ?? TranslationProviderOutput(provider: provider)
    }

    func prepareManualInput(notice: TranslationInlineNotice? = nil) {
        cancelTranslation()
        inputText = ""
        sourceSelection = .automatic
        targetSelection = .preferred
        resetOutput()
        inlineNotice = notice
        requestInputFocus()
    }

    func prepareSelectedText(_ text: String) {
        cancelTranslation()
        inputText = text
        sourceSelection = .automatic
        targetSelection = .preferred
        resetOutput()
        inlineNotice = nil
        requestInputFocus()
    }

    func updateInputText(_ text: String) {
        guard text != inputText else {
            return
        }
        cancelTranslation()
        inputText = text
        resetOutput()
        if !text.isEmpty {
            inlineNotice = nil
        }
    }

    func selectSourceLanguage(_ language: TranslationLanguage) {
        guard language != sourceSelection else {
            return
        }
        cancelTranslation()
        sourceSelection = language
        resetOutput()
    }

    func selectTargetLanguage(_ selection: TranslationTargetSelection) {
        guard selection != targetSelection else {
            return
        }
        cancelTranslation()
        targetSelection = selection
        resetOutput()
    }

    func swapLanguages() {
        cancelTranslation()
        let languages = resolvedLanguages()
        guard languages.source != .automatic else {
            resetOutput()
            inlineNotice = nil
            state = .failed
            errorMessage = "无法识别原文语言，请先手动选择来源语言。"
            return
        }

        sourceSelection = languages.target
        targetSelection = .language(languages.source)
        resetOutput()
    }

    func startTranslation() {
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            present(error: .emptyInput)
            return
        }
        let languages = resolvedLanguages()
        guard languages.source == .automatic || languages.source != languages.target else {
            present(error: .identicalLanguages)
            return
        }
        let request = TranslationRequest(
            text: text,
            sourceLanguage: languages.source,
            targetLanguage: languages.target
        )
        cancelTranslation()
        resetOutput()
        inlineNotice = nil
        detectedSourceLanguage = languages.source == .automatic ? nil : languages.source

        let requestID = UUID()
        activeRequestID = requestID
        for providerID in TranslationProviderID.allCases {
            do {
                let resolution = try providerRegistry.resolveProvider(for: providerID)
                if let displayModel = resolution.displayModel {
                    activeAIModel = displayModel
                }
                updateOutput(for: providerID) { output in
                    output.state = .translating
                    output.displayModel = resolution.displayModel
                    output.configurationWarning = resolution.configurationWarning
                }
                let provider = resolution.provider
                translationTasks[providerID] = Task { [weak self] in
                    guard let self else {
                        return
                    }
                    await self.translate(
                        with: provider,
                        providerID: providerID,
                        request: request,
                        requestID: requestID
                    )
                }
            } catch {
                let translationError = error as? TranslationError
                    ?? .missingConfiguration(error.localizedDescription)
                updateOutput(for: providerID) { output in
                    output.state = .failed
                    output.errorMessage = translationError.localizedDescription
                    output.needsSettings = translationError.suggestsOpeningSettings
                }
            }
        }
        refreshAggregateState()
    }

    func cancelTranslation() {
        translationTasks.values.forEach { $0.cancel() }
        translationTasks.removeAll()
        activeRequestID = nil

        for providerID in TranslationProviderID.allCases {
            updateOutput(for: providerID) { output in
                guard output.state == .translating else {
                    return
                }
                output.state = output.text.isEmpty ? .idle : .succeeded
            }
        }
        refreshAggregateState()
    }

    func copyResult(for provider: TranslationProviderID) {
        let text = output(for: provider).text
        guard !text.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        updateOutput(for: provider) { $0.didCopy = true }
        copyFeedbackTasks[provider]?.cancel()
        copyFeedbackTasks[provider] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.updateOutput(for: provider) { $0.didCopy = false }
        }
    }

    func requestInputFocus() {
        focusRequestID = UUID()
    }

    private func resolvedLanguages() -> ResolvedTranslationLanguages {
        languageResolver.resolve(
            text: inputText,
            sourceSelection: sourceSelection,
            targetSelection: targetSelection,
            preferredLanguage: settings.preferredLanguage,
            secondaryLanguage: settings.secondaryLanguage
        )
    }

    private func present(error: TranslationError, needsSettings: Bool = false) {
        inlineNotice = nil
        state = .failed
        errorMessage = error.localizedDescription
        self.needsSettings = needsSettings
    }

    private func translate(
        with provider: any TranslationProvider,
        providerID: TranslationProviderID,
        request: TranslationRequest,
        requestID: UUID
    ) async {
        do {
            for try await event in provider.translate(request) {
                try Task.checkCancellation()
                guard activeRequestID == requestID else {
                    return
                }
                switch event {
                case let .textDelta(text):
                    updateOutput(for: providerID) { $0.text += text }
                case let .completed(detectedLanguage):
                    if let detectedLanguage {
                        detectedSourceLanguage = detectedLanguage
                    }
                    updateOutput(for: providerID) { output in
                        output.state = output.text.isEmpty ? .failed : .succeeded
                        if output.text.isEmpty {
                            output.errorMessage = TranslationError.emptyResponse.localizedDescription
                        }
                    }
                }
            }

            guard activeRequestID == requestID else {
                return
            }
            updateOutput(for: providerID) { output in
                guard output.state == .translating else {
                    return
                }
                output.state = output.text.isEmpty ? .failed : .succeeded
                if output.text.isEmpty {
                    output.errorMessage = TranslationError.emptyResponse.localizedDescription
                }
            }
        } catch is CancellationError {
            finishCancellation(providerID: providerID, requestID: requestID)
        } catch let urlError as URLError where urlError.code == .cancelled {
            finishCancellation(providerID: providerID, requestID: requestID)
        } catch {
            guard activeRequestID == requestID else {
                return
            }
            let translationError = TranslationError.map(error)
            updateOutput(for: providerID) { output in
                output.state = .failed
                output.errorMessage = translationError.localizedDescription
                output.needsSettings = translationError.suggestsOpeningSettings
            }
        }

        guard activeRequestID == requestID else {
            return
        }
        translationTasks[providerID] = nil
        refreshAggregateState()
    }

    private func finishCancellation(
        providerID: TranslationProviderID,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else {
            return
        }
        updateOutput(for: providerID) { output in
            output.state = output.text.isEmpty ? .idle : .succeeded
        }
    }

    private func resetOutput() {
        copyFeedbackTasks.values.forEach { $0.cancel() }
        copyFeedbackTasks.removeAll()
        providerOutputs = Self.emptyProviderOutputs(aiModel: activeAIModel)
        detectedSourceLanguage = nil
        errorMessage = nil
        needsSettings = false
        state = .idle
    }

    private func updateOutput(
        for provider: TranslationProviderID,
        _ update: (inout TranslationProviderOutput) -> Void
    ) {
        var outputs = providerOutputs
        var output = outputs[provider] ?? TranslationProviderOutput(provider: provider)
        update(&output)
        outputs[provider] = output
        providerOutputs = outputs
    }

    private func refreshAggregateState() {
        let outputs = TranslationProviderID.allCases.map { output(for: $0) }
        if outputs.contains(where: { $0.state == .translating }) {
            state = .translating
            return
        }
        if outputs.contains(where: { !$0.text.isEmpty || $0.state == .succeeded }) {
            state = .succeeded
        } else if outputs.allSatisfy({ $0.state == .idle }) {
            state = .idle
        } else {
            state = .failed
        }
        activeRequestID = nil
    }

    private static func emptyProviderOutputs(
        aiModel: String
    ) -> [TranslationProviderID: TranslationProviderOutput] {
        Dictionary(uniqueKeysWithValues: TranslationProviderID.allCases.map { provider in
            var output = TranslationProviderOutput(provider: provider)
            if provider == .openAICompatible {
                output.displayModel = aiModel
            }
            return (provider, output)
        })
    }
}
