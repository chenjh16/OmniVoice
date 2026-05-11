import AppKit

enum ActionPanelAttributedTextBuilder {
    static func body(
        _ text: String,
        font: NSFont,
        color: NSColor,
        shadow: NSShadow?
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ActionPanelTextAlignmentPolicy.body
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if let shadow {
            attributes[.shadow] = shadow
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
