import AppKit
import Foundation

@MainActor
struct PermissionMenuPresenter {
    let strings: UIStrings
    let uiLanguage: UILanguage

    func entries(_ snapshot: PermissionSnapshot) -> [(label: String, granted: Bool)] {
        if uiLanguage == .chinese {
            return [
                ("麦克风", snapshot.microphoneGranted),
                ("辅助功能", snapshot.accessibilityGranted),
                ("输入监控", snapshot.inputMonitoringGranted),
                ("语音识别", snapshot.speechRecognitionGranted)
            ]
        }
        return [
            ("Microphone", snapshot.microphoneGranted),
            ("Accessibility", snapshot.accessibilityGranted),
            ("Input Monitoring", snapshot.inputMonitoringGranted),
            ("Speech Recognition", snapshot.speechRecognitionGranted)
        ]
    }

    func summaryItem(_ snapshot: PermissionSnapshot) -> NSMenuItem {
        let item = NSMenuItem(title: strings.permissionSummary(snapshot), action: nil, keyEquivalent: "")
        item.attributedTitle = summaryAttributedString(snapshot)
        item.toolTip = strings.permissionUsageTooltip
        item.isEnabled = true
        return item
    }

    func summaryAttributedString(_ snapshot: PermissionSnapshot) -> NSAttributedString {
        let output = NSMutableAttributedString(string: uiLanguage == .chinese ? "权限：" : "Permissions: ", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor
        ])
        for (index, entry) in entries(snapshot).enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: " · ", attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            output.append(statusAttributedString(
                text: strings.permissionDetail(entry.label, granted: entry.granted),
                granted: entry.granted
            ))
        }
        return output
    }

    func statusAttributedString(text: String, granted: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: granted
                ? NSColor(calibratedRed: 0.23, green: 0.58, blue: 0.35, alpha: 1.0)
                : NSColor(calibratedRed: 0.78, green: 0.25, blue: 0.22, alpha: 1.0)
        ])
    }
}
