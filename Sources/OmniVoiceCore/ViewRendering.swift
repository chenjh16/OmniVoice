import AppKit

extension NSView {
    func omniVoiceRenderedPNGData() -> Data? {
        layoutSubtreeIfNeeded()
        let rect = bounds
        guard rect.width > 0, rect.height > 0 else { return nil }
        guard let representation = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        displayIgnoringOpacity(rect, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return representation.representation(using: .png, properties: [:])
    }
}
