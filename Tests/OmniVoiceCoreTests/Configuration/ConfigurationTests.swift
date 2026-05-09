import Foundation
import Testing
@testable import OmniVoiceCore

@Suite("Configuration")
struct ConfigurationTests {}

extension ConfigurationTests {
    func jsoncObject(from url: URL) throws -> [String: Any] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let data = try #require(JSONCNormalizer.normalize(raw).data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
