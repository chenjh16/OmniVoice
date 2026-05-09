import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("Resources")
struct ResourceTests {
    @Test
    func appIconResourceExists() {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/AppIcon.icns")
        #expect(FileManager.default.fileExists(atPath: path.path))
    }
}
