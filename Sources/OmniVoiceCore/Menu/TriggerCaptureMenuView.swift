import AppKit
import Foundation

final class TriggerCaptureMenuView: NSView {
    private let button: NSButton
    private let hintLabel: NSTextField
    private let idleTitle: String
    private let idleHint: String
    private let captureTitle: String
    private let cancelHint: String
    private let onBegin: (TriggerCaptureMenuView) -> Void

    init(
        strings: UIStrings,
        selectedTriggerLabel: String,
        onBegin: @escaping (TriggerCaptureMenuView) -> Void
    ) {
        self.idleTitle = strings.recordTriggerKey
        self.idleHint = strings.language == .chinese ? "当前：\(selectedTriggerLabel)" : "Current: \(selectedTriggerLabel)"
        self.captureTitle = strings.recordingTriggerKey
        self.cancelHint = strings.language == .chinese ? "Esc 取消" : "Esc cancels"
        self.onBegin = onBegin
        self.button = NSButton(title: strings.recordTriggerKey, target: nil, action: nil)
        self.hintLabel = NSTextField(labelWithString: strings.triggerRecordingHelp)
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 38))
        toolTip = strings.tooltip(.triggerCapture)

        button.target = self
        button.action = #selector(beginPressed)
        button.bezelStyle = .rounded
        button.font = .menuFont(ofSize: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = strings.tooltip(.triggerCapture)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(button)
        addSubview(hintLabel)
        endCapture()

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayoutMetrics.customViewLeading),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),

            hintLabel.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 10),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginCapture() {
        button.title = captureTitle
        hintLabel.stringValue = cancelHint
        hintLabel.textColor = .secondaryLabelColor
    }

    func endCapture() {
        button.title = idleTitle
        hintLabel.stringValue = idleHint
        hintLabel.textColor = .secondaryLabelColor
    }

    func showRejected(_ message: String) {
        hintLabel.stringValue = message
        hintLabel.textColor = NSColor(calibratedRed: 0.78, green: 0.25, blue: 0.22, alpha: 1.0)
    }

    func showSelected(_ triggerLabel: String) {
        button.title = idleTitle
        hintLabel.stringValue = triggerLabel
        hintLabel.textColor = NSColor(calibratedRed: 0.23, green: 0.58, blue: 0.35, alpha: 1.0)
    }

    @objc private func beginPressed() {
        onBegin(self)
    }
}
