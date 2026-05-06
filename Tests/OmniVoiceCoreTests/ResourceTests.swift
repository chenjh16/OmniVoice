import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

@Suite("Resources")
struct ResourceTests {
    @Test
    func appIconResourceExists() {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.icns")
        #expect(FileManager.default.fileExists(atPath: path.path))
    }
}
