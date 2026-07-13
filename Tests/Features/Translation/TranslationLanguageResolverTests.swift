import XCTest
@testable import Invoker

final class TranslationLanguageResolverTests: XCTestCase {
    func testPreferredTargetUsesSecondaryLanguageWhenSourceMatchesPreferredLanguage() {
        let resolver = TranslationLanguageResolver { _ in .simplifiedChinese }

        let languages = resolver.resolve(
            text: "你好",
            sourceSelection: .automatic,
            targetSelection: .preferred,
            preferredLanguage: .simplifiedChinese,
            secondaryLanguage: .english
        )

        XCTAssertEqual(languages.source, .simplifiedChinese)
        XCTAssertEqual(languages.target, .english)
    }

    func testPreferredTargetUsesPreferredLanguageForOtherDetectedLanguages() {
        let resolver = TranslationLanguageResolver { _ in .english }

        let languages = resolver.resolve(
            text: "Hello",
            sourceSelection: .automatic,
            targetSelection: .preferred,
            preferredLanguage: .simplifiedChinese,
            secondaryLanguage: .english
        )

        XCTAssertEqual(languages.source, .english)
        XCTAssertEqual(languages.target, .simplifiedChinese)
    }

    func testFailedDetectionKeepsAutomaticSourceAndUsesPreferredTarget() {
        let resolver = TranslationLanguageResolver { _ in nil }

        let languages = resolver.resolve(
            text: "123",
            sourceSelection: .automatic,
            targetSelection: .preferred,
            preferredLanguage: .simplifiedChinese,
            secondaryLanguage: .english
        )

        XCTAssertEqual(languages.source, .automatic)
        XCTAssertEqual(languages.target, .simplifiedChinese)
    }

    func testExplicitSelectionsOverrideDetectionAndPreferredPair() {
        let resolver = TranslationLanguageResolver { _ in .english }

        let languages = resolver.resolve(
            text: "Bonjour",
            sourceSelection: .french,
            targetSelection: .language(.japanese),
            preferredLanguage: .simplifiedChinese,
            secondaryLanguage: .english
        )

        XCTAssertEqual(languages.source, .french)
        XCTAssertEqual(languages.target, .japanese)
    }
}
