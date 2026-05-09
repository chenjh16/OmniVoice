import AppKit

public final class OmniVoiceAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    public override init() {
        super.init()
    }

    @MainActor
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    @MainActor
    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
