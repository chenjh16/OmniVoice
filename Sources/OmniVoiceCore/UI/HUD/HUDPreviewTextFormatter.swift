import Foundation

enum HUDPreviewTextFormatter {
    static let defaultTailLimit = 44

    static func transcriptionTail(_ text: String, limit: Int = defaultTailLimit) -> String {
        guard text.count > limit else { return text }
        return "…" + text.suffix(limit)
    }
}
