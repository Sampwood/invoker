import Foundation

@MainActor
final class TwelveDataExchangeRates {
    struct Quote: Decodable {
        let symbol: String
        let rate: Decimal
        let timestamp: TimeInterval
    }

    enum LookupError: Error, Equatable {
        case invalidKey
        case accessDenied
        case rateLimited
        case unavailable

        init(statusCode: Int) {
            switch statusCode {
            case 401: self = .invalidKey
            case 403: self = .accessDenied
            case 429: self = .rateLimited
            default: self = .unavailable
            }
        }
    }

    private struct ErrorResponse: Decodable {
        let code: Int
    }

    private static let session = URLSession(configuration: .ephemeral)
    private let load: (URLRequest) async throws -> (Data, URLResponse)
    private let now: () -> ContinuousClock.Instant
    private var cached: (apiKey: String, quote: Quote, fetchedAt: ContinuousClock.Instant)?

    init(
        load: @escaping (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await session.data(for: request, delegate: NoRedirects())
        },
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.load = load
        self.now = now
    }

    func cachedQuote(for apiKey: String) -> Quote? {
        guard let cached, cached.apiKey == apiKey, now() - cached.fetchedAt < .seconds(60) else { return nil }
        return cached.quote
    }

    func invalidate() {
        cached = nil
    }

    func quote(for apiKey: String) async throws -> Quote {
        try Task.checkCancellation()
        guard !apiKey.isEmpty, apiKey.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw LookupError.invalidKey
        }
        if let cached = cachedQuote(for: apiKey) { return cached }

        let url = URL(string: "https://api.twelvedata.com/exchange_rate?symbol=USD%2FCNY")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("apikey " + apiKey, forHTTPHeaderField: "Authorization")
        let (data, response) = try await load(request)
        try Task.checkCancellation()

        guard let response = response as? HTTPURLResponse else { throw LookupError.unavailable }
        guard response.statusCode == 200 else { throw LookupError(statusCode: response.statusCode) }
        let decoder = JSONDecoder()
        if let error = try? decoder.decode(ErrorResponse.self, from: data) {
            throw LookupError(statusCode: error.code)
        }
        guard let quote = try? decoder.decode(Quote.self, from: data),
              quote.symbol == "USD/CNY", quote.rate > 0, !quote.rate.isNaN,
              quote.timestamp.isFinite, quote.timestamp > 0 else {
            throw LookupError.unavailable
        }
        cached = (apiKey, quote, now())
        return quote
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
