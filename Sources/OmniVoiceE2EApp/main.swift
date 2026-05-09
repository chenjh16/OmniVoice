import AppKit
import OmniVoiceCore
import OmniVoiceE2ESupport

if CommandLine.arguments.contains(InjectionE2ECommand.trigger) ||
    CommandLine.arguments.contains(InjectionE2ECommand.hudPreviewTrigger) {
    InjectionE2ECommand.runFromMain(arguments: CommandLine.arguments)
}

let app = NSApplication.shared
let delegate = OmniVoiceAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
