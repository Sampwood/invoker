import Foundation
import XCTest
@testable import Invoker

final class TranslationProviderTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.removeHandler()
        super.tearDown()
    }

    func testOpenAIRequestOmitsAuthorizationWhenAPIKeyIsEmpty() throws {
        let provider = OpenAICompatibleTranslationProvider(
            configuration: OpenAICompatibleConfiguration(
                baseURL: "http://localhost:11434/v1",
                model: "local-model",
                apiKey: ""
            ),
            session: makeStubSession()
        )

        let request = try provider.makeURLRequest(
            for: TranslationRequest(
                text: "Hello",
                sourceLanguage: .automatic,
                targetLanguage: .simplifiedChinese
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenAIRequestExpandsRootBaseURLToResponsesEndpoint() throws {
        let provider = OpenAICompatibleTranslationProvider(
            configuration: OpenAICompatibleConfiguration(
                baseURL: "https://example.com/",
                model: "example-model",
                apiKey: "secret-key"
            ),
            session: makeStubSession()
        )

        let request = try provider.makeURLRequest(
            for: TranslationRequest(
                text: "Hello",
                sourceLanguage: .english,
                targetLanguage: .simplifiedChinese
            )
        )

        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/responses")
    }

    func testResponsesRequestUsesVersionedBaseURLAndResponsesBody() throws {
        let provider = OpenAICompatibleTranslationProvider(
            configuration: OpenAICompatibleConfiguration(
                baseURL: "https://api.krill-ai.com/codex/v1",
                model: "gpt-5.5",
                apiKey: "secret-key"
            ),
            session: makeStubSession()
        )

        let request = try provider.makeURLRequest(
            for: TranslationRequest(
                text: "Hello",
                sourceLanguage: .english,
                targetLanguage: .simplifiedChinese
            )
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "https://api.krill-ai.com/codex/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
        XCTAssertEqual(json["model"] as? String, "gpt-5.5")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertFalse(try XCTUnwrap(json["instructions"] as? String).isEmpty)
        XCTAssertTrue(try XCTUnwrap(json["input"] as? String).contains("Hello"))
        XCTAssertNil(json["messages"])
    }

    func testResponsesStreamingResponseYieldsDeltasAndCompletion() async throws {
        URLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )
            )
            return URLProtocolStub.Response(
                response: response,
                chunks: [
                    Data("event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"\\u4f60\"}\n\n".utf8),
                    Data("event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"\\u597d\"}\n\n".utf8),
                    Data("event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\"}}\n\n".utf8),
                ]
            )
        }
        let provider = configuredOpenAIProvider()

        let events = try await collect(
            provider.translate(
                TranslationRequest(
                    text: "Hello",
                    sourceLanguage: .english,
                    targetLanguage: .simplifiedChinese
                )
            )
        )

        XCTAssertEqual(
            events,
            [.textDelta("你"), .textDelta("好"), .completed(detectedSourceLanguage: nil)]
        )
    }

    func testResponsesJSONResponseFallsBackWithoutSecondRequest() async throws {
        var requestCount = 0
        URLProtocolStub.setHandler { request in
            requestCount += 1
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                "{\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"\\u4f60\\u597d\"}]}]}".utf8
            )
            return URLProtocolStub.Response(response: response, chunks: [data])
        }
        let provider = configuredOpenAIProvider()

        let events = try await collect(
            provider.translate(
                TranslationRequest(
                    text: "Hello",
                    sourceLanguage: .english,
                    targetLanguage: .simplifiedChinese
                )
            )
        )

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(events, [.textDelta("你好"), .completed(detectedSourceLanguage: nil)])
    }

    func testOpenAIRejectedEndpointSuggestsCorrectingSettings() async throws {
        URLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 405, httpVersion: nil, headerFields: nil)
            )
            return URLProtocolStub.Response(response: response, chunks: [Data()])
        }
        let provider = configuredOpenAIProvider()

        do {
            _ = try await collect(
                provider.translate(
                    TranslationRequest(
                        text: "Hello",
                        sourceLanguage: .english,
                        targetLanguage: .simplifiedChinese
                    )
                )
            )
            XCTFail("Expected endpoint rejection")
        } catch {
            let translationError = error as? TranslationError
            XCTAssertEqual(translationError, .endpointRejected(statusCode: 405))
            XCTAssertEqual(translationError?.suggestsOpeningSettings, true)
        }
    }

    func testDeepLFreeAndProKeysChooseDifferentOfficialHosts() throws {
        let freeProvider = DeepLTranslationProvider(
            configuration: DeepLConfiguration(authKey: "free-key:fx"),
            session: makeStubSession()
        )
        let proProvider = DeepLTranslationProvider(
            configuration: DeepLConfiguration(authKey: "pro-key"),
            session: makeStubSession()
        )
        let translationRequest = TranslationRequest(
            text: "Hello",
            sourceLanguage: .automatic,
            targetLanguage: .simplifiedChinese
        )

        let freeRequest = try freeProvider.makeURLRequest(for: translationRequest)
        let proRequest = try proProvider.makeURLRequest(for: translationRequest)

        XCTAssertEqual(freeRequest.url?.host, "api-free.deepl.com")
        XCTAssertEqual(proRequest.url?.host, "api.deepl.com")
        XCTAssertEqual(freeRequest.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key free-key:fx")
        XCTAssertFalse(String(data: freeRequest.httpBody ?? Data(), encoding: .utf8)?.contains("source_lang") == true)
    }

    func testDeepLResponseIncludesDetectedSourceLanguage() async throws {
        URLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let data = Data(
                "{\"translations\":[{\"detected_source_language\":\"EN\",\"text\":\"\\u4f60\\u597d\"}]}".utf8
            )
            return URLProtocolStub.Response(response: response, chunks: [data])
        }
        let provider = DeepLTranslationProvider(
            configuration: DeepLConfiguration(authKey: "free-key:fx"),
            session: makeStubSession()
        )

        let events = try await collect(
            provider.translate(
                TranslationRequest(
                    text: "Hello",
                    sourceLanguage: .automatic,
                    targetLanguage: .simplifiedChinese
                )
            )
        )

        XCTAssertEqual(
            events,
            [.textDelta("你好"), .completed(detectedSourceLanguage: .english)]
        )
    }

    func testDeepLRateLimitMapsToTypedError() async throws {
        URLProtocolStub.setHandler { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)
            )
            return URLProtocolStub.Response(response: response, chunks: [Data()])
        }
        let provider = DeepLTranslationProvider(
            configuration: DeepLConfiguration(authKey: "free-key:fx"),
            session: makeStubSession()
        )

        do {
            _ = try await collect(
                provider.translate(
                    TranslationRequest(
                        text: "Hello",
                        sourceLanguage: .automatic,
                        targetLanguage: .simplifiedChinese
                    )
                )
            )
            XCTFail("Expected rate limit error")
        } catch {
            XCTAssertEqual(error as? TranslationError, .rateLimited)
        }
    }

    private func configuredOpenAIProvider() -> OpenAICompatibleTranslationProvider {
        OpenAICompatibleTranslationProvider(
            configuration: OpenAICompatibleConfiguration(
                baseURL: "https://example.com/v1",
                model: "example-model",
                apiKey: "secret-key"
            ),
            session: makeStubSession()
        )
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func collect(
        _ stream: AsyncThrowingStream<TranslationEvent, Error>
    ) async throws -> [TranslationEvent] {
        var events: [TranslationEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private final class URLProtocolStub: URLProtocol {
    struct Response {
        let response: HTTPURLResponse
        let chunks: [Data]
    }

    typealias Handler = (URLRequest) throws -> Response

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func removeHandler() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let stub = try handler(request)
            client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
            for chunk in stub.chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
