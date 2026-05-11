import Foundation

enum RestartAppPlanner {
    static func bundleURL(
        currentBundleURL: URL,
        fallbackApplicationsURL: URL = URL(fileURLWithPath: "/Applications/OmniVoice.app")
    ) -> URL {
        currentBundleURL.pathExtension == "app" ? currentBundleURL : fallbackApplicationsURL
    }
}
