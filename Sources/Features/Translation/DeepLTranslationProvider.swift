import Foundation

struct DeepLConfiguration: Equatable, Sendable {
    let authKey: String
}

final class DeepLTranslationProvider: TranslationProvider, @unchecked Sendable {
    let id = TranslationProviderID.deepL

    private let configuration: DeepLConfiguration
    private let session: URLSession

    init(
        configuration: DeepLConfiguration,
        session: URLSession = TranslationNetworkSupport.makeEphemeralSession()
    ) {
        self.configuration = configuration
        self.session = session
    }

    func translate(
        _ request: TranslationRequest
    ) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    let urlRequest = try makeURLRequest(for: request)
                    let (data, response) = try await session.data(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TranslationError.responseDecodingFailed
                    }
                    guard (200 ... 299).contains(httpResponse.statusCode) else {
                        throw TranslationNetworkSupport.error(
                            statusCode: httpResponse.statusCode,
                            data: data
                        )
                    }

                    let deepLResponse: DeepLResponse
                    do {
                        deepLResponse = try JSONDecoder().decode(DeepLResponse.self, from: data)
                    } catch {
                        throw TranslationError.responseDecodingFailed
                    }
                    guard let translation = deepLResponse.translations.first,
                          !translation.text.isEmpty
                    else {
                        throw TranslationError.emptyResponse
                    }

                    try Task.checkCancellation()
                    continuation.yield(.textDelta(translation.text))
                    continuation.yield(
                        .completed(
                            detectedSourceLanguage: translation.detectedSourceLanguage
                                .flatMap(TranslationLanguage.init(deepLDetectedCode:))
                        )
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: TranslationError.map(error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func makeURLRequest(for request: TranslationRequest) throws -> URLRequest {
        let authKey = configuration.authKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authKey.isEmpty else {
            throw TranslationError.missingConfiguration("请在设置中填写 DeepL Auth Key。")
        }
        guard let targetLanguage = request.targetLanguage.deepLTargetCode else {
            throw TranslationError.unsupportedLanguage(id, request.targetLanguage)
        }

        let host = authKey.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        guard let url = URL(string: "https://\(host)/v2/translate") else {
            throw TranslationError.invalidEndpoint
        }

        var queryItems = [
            URLQueryItem(name: "text", value: request.text),
            URLQueryItem(name: "target_lang", value: targetLanguage),
        ]
        if let sourceLanguage = request.sourceLanguage.deepLSourceCode {
            queryItems.append(URLQueryItem(name: "source_lang", value: sourceLanguage))
        }
        var components = URLComponents()
        components.queryItems = queryItems
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw TranslationError.responseDecodingFailed
        }

        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("DeepL-Auth-Key \(authKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = body
        return urlRequest
    }
}

private struct DeepLResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let detectedSourceLanguage: String?
        let text: String

        enum CodingKeys: String, CodingKey {
            case detectedSourceLanguage = "detected_source_language"
            case text
        }
    }
}
