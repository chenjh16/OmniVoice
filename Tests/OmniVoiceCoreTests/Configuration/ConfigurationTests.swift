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

    func configFixture(slug: String) throws -> ConfigTestFixture {
        try ConfigTestFixture(slug: slug)
    }
}

struct ConfigTestFixture {
    let directory: URL
    let configURL: URL

    init(slug: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(slug)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configURL = directory.appendingPathComponent("config.jsonc")
    }

    var loader: ConfigLoader {
        ConfigLoader(configFileURL: configURL)
    }

    func write(_ text: String, permissions: Int = 0o600) throws {
        try Data(text.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: configURL.path)
    }

    func object() throws -> [String: Any] {
        let raw = try String(contentsOf: configURL, encoding: .utf8)
        let data = try #require(JSONCNormalizer.normalize(raw).data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func backupNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("config.jsonc.bak-") }
    }
}
