import AppKit
import OmniVoiceCore

let app = NSApplication.shared
let delegate = OmniVoiceAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
