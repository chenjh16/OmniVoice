import Foundation

public enum RestartAppPlanner {
    public static func bundleURL(
        currentBundleURL: URL,
        fallbackApplicationsURL: URL = URL(fileURLWithPath: "/Applications/OmniVoice.app")
    ) -> URL {
        currentBundleURL.pathExtension == "app" ? currentBundleURL : fallbackApplicationsURL
    }
}
