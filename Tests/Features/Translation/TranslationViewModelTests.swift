import XCTest
@testable import Invoker

@MainActor
final class TranslationViewModelTests: XCTestCase {
    func testNewTranslationCancelsAndIgnoresLateEventsFromPreviousRequest() async throws {
        let suiteName = "TranslationViewModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = TranslationSettingsStore(
            userDefaults: defaults,
            secretStore: ViewModelInMemorySecretStore(),
            legacyKeychain: nil,
            ccSwitchReader: ViewModelUnavailableCCSwitchReader()
        )
        let provider = TextEchoTranslationProvider()
        let viewModel = TranslationViewModel(
            settings: settings,
            providerRegistry: FixedTranslationProviderRegistry(provider: provider),
            languageResolver: TranslationLanguageResolver { _ in .english }
        )

        viewModel.prepareSelectedText("first")
        viewModel.startTranslation()
        viewModel.updateInputText("second")
        viewModel.startTranslation()

        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(viewModel.resultText, "second-result")
        XCTAssertEqual(viewModel.state, .succeeded)
    }

    func testCancelDoesNotSurfaceAsFailure() async throws {
        let suiteName = "TranslationViewModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = TranslationSettingsStore(
            userDefaults: defaults,
            secretStore: ViewModelInMemorySecretStore(),
            legacyKeychain: nil,
            ccSwitchReader: ViewModelUnavailableCCSwitchReader()
        )
        let viewModel = TranslationViewModel(
            settings: settings,
            providerRegistry: FixedTranslationProviderRegistry(provider: TextEchoTranslationProvider()),
            languageResolver: TranslationLanguageResolver { _ in .english }
        )

        viewModel.prepareSelectedText("first")
        viewModel.startTranslation()
        viewModel.cancelTranslation()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(viewModel.resultText.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailedSwapWhileTranslatingIgnoresLateEvents() async throws {
        let suiteName = "TranslationViewModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = TranslationSettingsStore(
            userDefaults: defaults,
            secretStore: ViewModelInMemorySecretStore(),
            legacyKeychain: nil,
            ccSwitchReader: ViewModelUnavailableCCSwitchReader()
        )
        let provider = LateEventTranslationProvider()
        let viewModel = TranslationViewModel(
            settings: settings,
            providerRegistry: FixedTranslationProviderRegistry(provider: provider),
            languageResolver: TranslationLanguageResolver { _ in nil }
        )

        viewModel.prepareSelectedText("unrecognized")
        viewModel.startTranslation()
        XCTAssertEqual(viewModel.state, .translating)

        viewModel.swapLanguages()

        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertTrue(viewModel.resultText.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            "无法识别原文语言，请先手动选择来源语言。"
        )

        provider.yield(.textDelta("late result"))
        provider.yield(.completed(detectedSourceLanguage: .english))
        provider.finish()
        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertTrue(viewModel.resultText.isEmpty)
        XCTAssertNil(viewModel.detectedSourceLanguage)
        XCTAssertEqual(
            viewModel.errorMessage,
            "无法识别原文语言，请先手动选择来源语言。"
        )
    }

    func testNewErrorClearsExistingInlineNotice() throws {
        let suiteName = "TranslationViewModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = TranslationSettingsStore(
            userDefaults: defaults,
            secretStore: ViewModelInMemorySecretStore(),
            legacyKeychain: nil,
            ccSwitchReader: ViewModelUnavailableCCSwitchReader()
        )
        let viewModel = TranslationViewModel(
            settings: settings,
            providerRegistry: FixedTranslationProviderRegistry(
                provider: TextEchoTranslationProvider()
            )
        )

        viewModel.prepareManualInput(notice: .noSelectedText)
        XCTAssertEqual(viewModel.inlineNotice, .noSelectedText)

        viewModel.startTranslation()

        XCTAssertNil(viewModel.inlineNotice)
        XCTAssertEqual(viewModel.state, .failed)
        XCTAssertEqual(
            viewModel.errorMessage,
            TranslationError.emptyInput.localizedDescription
        )
    }

    func testPanelContentSizingGrowsUntilItsSectionAndPanelLimits() {
        let longText = String(repeating: "dynamic translation content ", count: 200)

        XCTAssertEqual(
            TranslationPanelContentSizing.sourceHeight(
                text: longText,
                panelWidth: TranslationPanelContentSizing.defaultWidth
            ),
            160,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TranslationPanelContentSizing.detailHeight(
                state: .succeeded,
                inlineNotice: nil,
                errorMessage: nil,
                resultText: longText,
                panelWidth: TranslationPanelContentSizing.defaultWidth
            ),
            220,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TranslationPanelContentSizing.panelHeight(
                state: .failed,
                inlineNotice: nil,
                errorMessage: longText,
                inputText: longText,
                resultText: longText,
                panelWidth: TranslationPanelContentSizing.defaultWidth
            ),
            TranslationPanelContentSizing.maximumPanelHeight,
            accuracy: 0.001
        )
    }

    func testPanelContentSizingAccountsForNarrowerTextWrapping() {
        let text = String(repeating: "一段需要自动换行的文本", count: 12)
        let wideHeight = TranslationPanelContentSizing.sourceHeight(
            text: text,
            panelWidth: 520
        )
        let narrowHeight = TranslationPanelContentSizing.sourceHeight(
            text: text,
            panelWidth: 380
        )

        XCTAssertGreaterThanOrEqual(narrowHeight, wideHeight)
        XCTAssertEqual(
            TranslationPanelContentSizing.panelHeight(
                state: .translating,
                inlineNotice: nil,
                errorMessage: nil,
                inputText: "",
                resultText: "",
                panelWidth: TranslationPanelContentSizing.defaultWidth
            ),
            TranslationPanelContentSizing.expandedMinimumPanelHeight,
            accuracy: 0.001
        )
    }
}

private final class TextEchoTranslationProvider: TranslationProvider, @unchecked Sendable {
    let id = TranslationProviderID.openAICompatible

    func translate(
        _ request: TranslationRequest
    ) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if request.text == "first" {
                        try await Task.sleep(nanoseconds: 120_000_000)
                    }
                    try Task.checkCancellation()
                    continuation.yield(.textDelta("\(request.text)-result"))
                    continuation.yield(.completed(detectedSourceLanguage: .english))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class LateEventTranslationProvider: TranslationProvider {
    let id = TranslationProviderID.openAICompatible

    private let stream: AsyncThrowingStream<TranslationEvent, Error>
    private let continuation: AsyncThrowingStream<TranslationEvent, Error>.Continuation

    init() {
        let pair = AsyncThrowingStream<TranslationEvent, Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func translate(
        _ request: TranslationRequest
    ) -> AsyncThrowingStream<TranslationEvent, Error> {
        stream
    }

    func yield(_ event: TranslationEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }
}

@MainActor
private final class FixedTranslationProviderRegistry: TranslationProviderResolving {
    private let provider: any TranslationProvider

    init(provider: any TranslationProvider) {
        self.provider = provider
    }

    func resolveProvider(for id: TranslationProviderID) throws -> TranslationProviderResolution {
        TranslationProviderResolution(
            provider: provider,
            displayModel: id == .openAICompatible ? "test-model" : nil,
            configurationWarning: nil
        )
    }
}

private final class ViewModelInMemorySecretStore: TranslationSecretStoring {
    let fileURL = URL(fileURLWithPath: "/tmp/invoker-view-model-test-config.json")
    private var secrets = TranslationSecrets.empty

    func fileExists() -> Bool {
        false
    }

    func load() throws -> TranslationSecrets {
        secrets
    }

    func save(_ secrets: TranslationSecrets) throws {
        self.secrets = secrets
    }
}

private struct ViewModelUnavailableCCSwitchReader: CCSwitchAIConfigurationReading {
    func currentConfiguration() throws -> CCSwitchAIConfiguration {
        throw AIConfigurationError.ccSwitchDatabaseUnavailable
    }
}
