import AppKit
import Testing
@testable import OmniVoiceCore

@Suite("ActionPanel text builder")
struct ActionPanelTextBuilderTests {
    @Test
    func bodyTextBuilderKeepsNaturalAlignmentAndOptionalShadow() {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 1
        let text = ActionPanelAttributedTextBuilder.body(
            "hello",
            font: .systemFont(ofSize: 14),
            color: .white,
            shadow: shadow
        )
        #expect(text.string == "hello")
        let actualShadow = text.attribute(.shadow, at: 0, effectiveRange: nil) as? NSShadow
        #expect(actualShadow === shadow)
        let paragraph = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(paragraph?.alignment == ActionPanelTextAlignmentPolicy.body)
    }
}
