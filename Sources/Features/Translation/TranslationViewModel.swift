import AppKit
import Combine
import Foundation

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published private(set) var inputText = ""
    @Published private(set) var resultText = ""
    @Published private(set) var sourceSelection = TranslationLanguage.automatic
    @Published private(set) var targetSelection = TranslationTargetSelection.preferred
    @Published private(set) var selectedProvider: TranslationProviderID
    @Published private(set) var state = TranslationViewState.idle
    @Published private(set) var detectedSourceLanguage: TranslationLanguage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var inlineNotice: TranslationInlineNotice?
    @Published private(set) var needsSettings = false
    @Published private(set) var didCopyResult = false
    @Published private(set) var focusRequestID = UUID()
    @Published private(set) var activeAIModel: String
    @Published private(set) var configurationWarning: String?

    let settings: TranslationSettingsStore

    private let providerRegistry: TranslationProviderResolving
    private let languageResolver: TranslationLanguageResolver
    private var translationTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?
    private var activeRequestID: UUID?

    init(
        settings: TranslationSettingsStore,
        providerRegistry: TranslationProviderResolving,
        languageResolver: TranslationLanguageResolver = TranslationLanguageResolver()
    ) {
        self.settings = settings
        self.providerRegistry = providerRegistry
        self.languageResolver = languageResolver
        selectedProvider = settings.activeProvider
        activeAIModel = settings.effectiveAIModel
        configurationWarning = nil
    }

    var canTranslate: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prepareManualInput(notice: TranslationInlineNotice? = nil) {
        cancelTranslation()
        selectedProvider = settings.activeProvider
        inputText = ""
        sourceSelection = .automatic
        targetSelection = .preferred
        resetOutput()
        inlineNotice = notice
        requestInputFocus()
    }

    func prepareSelectedText(_ text: String) {
        cancelTranslation()
        selectedProvider = settings.activeProvider
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

    func selectProvider(_ provider: TranslationProviderID) {
        guard provider != selectedProvider else {
            return
        }
        cancelTranslation()
        selectedProvider = provider
        settings.activeProvider = provider
        resetOutput()
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
        let providerResolution: TranslationProviderResolution
        do {
            providerResolution = try providerRegistry.resolveProvider(for: selectedProvider)
        } catch {
            configurationWarning = nil
            let translationError = error as? TranslationError
                ?? .missingConfiguration(error.localizedDescription)
            present(error: translationError, needsSettings: true)
            return
        }
        let provider = providerResolution.provider
        if let displayModel = providerResolution.displayModel {
            activeAIModel = displayModel
        }
        configurationWarning = providerResolution.configurationWarning

        cancelTranslation()
        resultText = ""
        errorMessage = nil
        inlineNotice = nil
        needsSettings = false
        detectedSourceLanguage = languages.source == .automatic ? nil : languages.source
        didCopyResult = false
        state = .translating

        let requestID = UUID()
        activeRequestID = requestID
        translationTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                for try await event in provider.translate(request) {
                    try Task.checkCancellation()
                    guard activeRequestID == requestID else {
                        return
                    }
                    switch event {
                    case let .textDelta(text):
                        resultText += text
                    case let .completed(detectedLanguage):
                        if let detectedLanguage {
                            detectedSourceLanguage = detectedLanguage
                        }
                        state = resultText.isEmpty ? .failed : .succeeded
                        if resultText.isEmpty {
                            errorMessage = TranslationError.emptyResponse.localizedDescription
                        }
                    }
                }

                guard activeRequestID == requestID else {
                    return
                }
                if state == .translating {
                    if resultText.isEmpty {
                        present(error: .emptyResponse)
                    } else {
                        state = .succeeded
                    }
                }
                activeRequestID = nil
                translationTask = nil
            } catch is CancellationError {
                finishCancellation(requestID: requestID)
            } catch let urlError as URLError where urlError.code == .cancelled {
                finishCancellation(requestID: requestID)
            } catch {
                guard activeRequestID == requestID else {
                    return
                }
                let translationError = TranslationError.map(error)
                present(
                    error: translationError,
                    needsSettings: translationError.suggestsOpeningSettings
                )
                activeRequestID = nil
                translationTask = nil
            }
        }
    }

    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        activeRequestID = nil
        if state == .translating {
            state = resultText.isEmpty ? .idle : .succeeded
        }
    }

    func copyResult() {
        guard !resultText.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resultText, forType: .string)

        didCopyResult = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.didCopyResult = false
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

    private func finishCancellation(requestID: UUID) {
        guard activeRequestID == requestID else {
            return
        }
        activeRequestID = nil
        translationTask = nil
        state = resultText.isEmpty ? .idle : .succeeded
    }

    private func resetOutput() {
        resultText = ""
        detectedSourceLanguage = nil
        errorMessage = nil
        needsSettings = false
        didCopyResult = false
        configurationWarning = nil
        state = .idle
    }
}
