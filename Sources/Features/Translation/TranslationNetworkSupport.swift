import Foundation

enum TranslationNetworkSupport {
    static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }

    static func data(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
        }
        return data
    }

    static func error(statusCode: Int, data: Data) -> TranslationError {
        switch statusCode {
        case 401, 403:
            return .authenticationFailed
        case 408:
            return .timedOut
        case 429:
            if responseErrorCode(from: data) == "insufficient_quota" {
                return .quotaExceeded
            }
            return .rateLimited
        case 456:
            return .quotaExceeded
        default:
            return .http(statusCode: statusCode, message: responseMessage(from: data))
        }
    }

    private static func responseMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        if let message = dictionary["message"] as? String {
            return message
        }
        if let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    private static func responseErrorCode(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let error = dictionary["error"] as? [String: Any]
        else {
            return nil
        }
        return error["code"] as? String
    }
}
