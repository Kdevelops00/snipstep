import Foundation
import Vision
import ImageIO

public protocol OCRRecognizing: Sendable {
    func recognize(url: URL) async throws -> OCRResult
}

public actor VisionOCR: OCRRecognizing {
    public init() {}
    public func recognize(url: URL) async throws -> OCRResult {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: url)
        try handler.perform([request])
        try Task.checkCancellation()
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return OCRResult(state: text.isEmpty ? .empty : .recognized, text: text)
    }
}
