import Foundation
import ImageIO
import Vision

protocol ClipboardOCRRecognizing: Sendable {
    func recognizeText(in pngData: Data) async throws -> String?
}

enum ClipboardOCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "无法读取图片以进行文字识别"
    }
}

struct VisionClipboardOCRRecognizer: ClipboardOCRRecognizing {
    func recognizeText(in pngData: Data) async throws -> String? {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw ClipboardOCRError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let text = request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }.value
    }
}
