import Foundation

struct ASRRecognitionDiagnosticSummary: Equatable, Sendable {
    let textCharacterCount: Int
    let lowConfidenceSegmentCount: Int
    let alternativeCount: Int
    let allowedAppleServerRecognition: Bool

    init(result: ASRRecognitionResult) {
        textCharacterCount = result.text.count
        lowConfidenceSegmentCount = result.lowConfidenceSegments.count
        alternativeCount = result.alternatives.count
        allowedAppleServerRecognition = result.allowedAppleServerRecognition
    }

    var details: [String: String] {
        [
            "draft_chars": "\(textCharacterCount)",
            "low_confidence_segments": "\(lowConfidenceSegmentCount)",
            "alternatives": "\(alternativeCount)",
            "apple_online_allowed": allowedAppleServerRecognition ? "true" : "false"
        ]
    }

    var liveDetails: [String: String] {
        [
            "draft_chars": "\(textCharacterCount)",
            "apple_online_allowed": allowedAppleServerRecognition ? "true" : "false"
        ]
    }
}
