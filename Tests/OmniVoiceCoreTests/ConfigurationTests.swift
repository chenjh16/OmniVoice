import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

@Suite("Configuration")
struct ConfigurationTests {
    @Test
    func configLoaderReadsJSONCSourcesAndRedactsSecrets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          // JSONC comments are allowed.
          "active_source": "cn",
          "default_model": "mimo-v2.5",
          "sources": {
            "sgp": {
              "base_url": "https://sgp.example.test/v1",
              "api_key": "sgp-secret",
            },
            "cn": {
              "base_url": "https://cn.example.test/v1",
              "api_key": "cn-secret",
            },
          },
          "latency": {
            "enabled": true,
            "interval_seconds": 900,
          },
          "custom_styles": {
            "support_reply": {
              "display_name": "Support Reply",
              "display_name_zh": "客服回复",
              "description": "Short support response",
              "description_zh": "简短客服回复",
              "prompt_lines": [
                "Turn speech into a concise support reply.",
                "Do not invent policy, refund amounts, or deadlines."
              ],
            },
            "bad style": {
              "display_name": "Bad",
              "prompt": "ignored"
            },
            "empty_prompt": {
              "display_name": "Empty",
              "prompt": ""
            },
          },
        }
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        let loader = ConfigLoader(configFileURL: configURL)

        let config = loader.load()
        #expect(config.baseURL.absoluteString == "https://cn.example.test")
        #expect(config.apiKey == "cn-secret")
        #expect(config.defaultModel == .mimoV25)
        #expect(config.source == .configFile)
        #expect(config.activeSourceID == "cn")
        #expect(config.resolvedSourceID == "cn")
        #expect(config.sources.count == 2)
        #expect(config.latencySettings.interval == .minutes15)
        #expect(config.customStyles.count == 1)
        #expect(config.customStyles.first?.id == "support_reply")
        #expect(config.customStyles.first?.displayNameZH == "客服回复")
        #expect(config.customStyles.first?.prompt.contains("refund amounts") == true)
        #expect(config.redactedStatus.baseURLHost == "cn.example.test")
        #expect(config.redactedStatus.apiKeyConfigured)
        #expect(config.redactedStatus.apiKeyPreview == "••••••")
        #expect(!config.redactedStatus.displayLines.joined().contains("cn-secret"))
    }
    @Test
    func configLoaderOnlyAcceptsJSONCMultiSourceSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-config-canonical-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsoncURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          "base_url": "https://old.example.test",
          "api_key": "old-secret",
          "default_model": "mimo-v2.5"
        }
        """.utf8).write(to: jsoncURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: jsoncURL.path)

        let legacyShape = ConfigLoader(configFileURL: jsoncURL).load()
        #expect(legacyShape.source == .missing)
        #expect(legacyShape.apiKey == nil)
        #expect(legacyShape.warnings.contains("Config warning: config.jsonc must use sources"))

        let fallbackURL = directory.appendingPathComponent("config.json")
        try Data("""
        {
          "active_source": "fallback",
          "sources": {
            "fallback": {
              "base_url": "https://fallback.example.test",
              "api_key": "fallback-secret"
            }
          }
        }
        """.utf8).write(to: fallbackURL)
        let missingFallback = ConfigLoader(configFileURL: directory.appendingPathComponent("missing.jsonc")).load()
        #expect(missingFallback.source == .missing)
        #expect(missingFallback.apiKey == nil)
    }
    @Test
    func configMenuStateWritesPreserveUnknownFieldsAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-save-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          "active_source": "primary",
          "default_model": "mimo-v2.5",
          "custom_flag": true,
          "sources": {
            "primary": {
              "base_url": "https://old.example.test",
              "api_key": "old-secret"
            },
            "backup": {
              "base_url": "https://backup.example.test",
              "api_key": "backup-secret"
            }
          },
          "custom_styles": {
            "meeting_notes": {
              "display_name": "Meeting Notes",
              "prompt": "Keep action items."
            }
          }
        }
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)

        let loader = ConfigLoader(configFileURL: configURL)
        #expect(loader.saveActiveSource("backup"))
        #expect(loader.saveLatencyInterval(.startupOnly))

        let data = try Data(contentsOf: configURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["default_model"] as? String == "mimo-v2.5")
        #expect(object["custom_flag"] as? Bool == true)
        #expect(object["active_source"] as? String == "backup")
        let sources = try #require(object["sources"] as? [String: Any])
        let primary = try #require(sources["primary"] as? [String: Any])
        let backup = try #require(sources["backup"] as? [String: Any])
        #expect(primary["base_url"] as? String == "https://old.example.test")
        #expect(primary["api_key"] as? String == "old-secret")
        #expect(backup["base_url"] as? String == "https://backup.example.test")
        #expect(backup["api_key"] as? String == "backup-secret")
        let customStyles = try #require(object["custom_styles"] as? [String: Any])
        let meetingNotes = try #require(customStyles["meeting_notes"] as? [String: Any])
        #expect(meetingNotes["prompt"] as? String == "Keep action items.")
        let latency = try #require(object["latency"] as? [String: Any])
        #expect(latency["enabled"] as? Bool == true)
        #expect(latency["interval_seconds"] is NSNull)
        let permissions = try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber
        #expect((permissions?.intValue ?? 0) & 0o777 == 0o600)
    }
    @Test
    func configSourceNamesAndTemplates() throws {
        #expect(ConfigSourceNameValidator.isValid("config1"))
        #expect(ConfigSourceNameValidator.isValid("work-cn_1"))
        #expect(!ConfigSourceNameValidator.isValid(""))
        #expect(!ConfigSourceNameValidator.isValid("auto"))
        #expect(!ConfigSourceNameValidator.isValid("bad name"))
        #expect(CustomTranscriptionStyleValidator.isValidID("meeting_notes"))
        #expect(!CustomTranscriptionStyleValidator.isValidID("bad style"))
        #expect(!CustomTranscriptionStyleValidator.isValidID("concise"))
        #expect(CustomTranscriptionStyleValidator.isValidPrompt("整理成会议纪要"))
        #expect(!CustomTranscriptionStyleValidator.isValidPrompt(""))

        let chineseTemplate = ConfigTemplateBuilder.template(uiLanguage: .chinese)
        #expect(chineseTemplate.contains(#""active_source": "auto""#))
        #expect(chineseTemplate.contains(#""interval_seconds": 1800"#))
        #expect(chineseTemplate.contains(#""custom_styles""#))
        #expect(chineseTemplate.contains("自定义转写风格"))
        #expect(chineseTemplate.contains("OmniVoice 会读取"))
        let englishTemplate = ConfigTemplateBuilder.template(uiLanguage: .english)
        #expect(englishTemplate.contains("OmniVoice reads this file"))
        #expect(englishTemplate.contains(#""sources""#))
        #expect(englishTemplate.contains("Custom transcription styles"))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-source-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        let loader = ConfigLoader(configFileURL: configURL)
        #expect(loader.createTemplateIfMissing(uiLanguage: .english))
        #expect(FileManager.default.fileExists(atPath: configURL.path))
        let rawTemplate = try String(contentsOf: configURL, encoding: .utf8)
        let data = try #require(JSONCNormalizer.normalize(rawTemplate).data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["active_source"] as? String == "auto")
        let sources = try #require(object["sources"] as? [String: Any])
        let config1 = try #require(sources["config1"] as? [String: Any])
        #expect(config1["base_url"] as? String == "https://token-plan-sgp.xiaomimimo.com")
        #expect(config1["api_key"] as? String == "")
    }
    @Test
    func configFileOpenPlannerPrefersCodeEditorsThenFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-editor-plan-\(UUID().uuidString)", isDirectory: true)
        let apps = root.appendingPathComponent("Applications", isDirectory: true)
        let homeApps = root.appendingPathComponent("HomeApplications", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeApps, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cursorBundle = homeApps.appendingPathComponent("Cursor.app", isDirectory: true)
        try FileManager.default.createDirectory(at: cursorBundle, withIntermediateDirectories: true)
        let appPlan = ConfigFileOpenPlanner.plan(
            applicationsDirectories: [apps, homeApps],
            executableDirectories: [bin]
        )
        #expect(appPlan.method == .applicationBundle(cursorBundle, displayName: "Cursor"))

        try FileManager.default.removeItem(at: cursorBundle)
        let codeCommand = bin.appendingPathComponent("code")
        try Data("#!/bin/sh\n".utf8).write(to: codeCommand)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codeCommand.path)
        let commandPlan = ConfigFileOpenPlanner.plan(
            applicationsDirectories: [apps, homeApps],
            executableDirectories: [bin]
        )
        #expect(commandPlan.method == .command(codeCommand, displayName: "Visual Studio Code"))

        let fallbackPlan = ConfigFileOpenPlanner.plan(
            applicationsDirectories: [root.appendingPathComponent("missing-apps", isDirectory: true)],
            executableDirectories: [root.appendingPathComponent("missing-bin", isDirectory: true)]
        )
        #expect(fallbackPlan.method == .systemDefault)
    }
    @Test
    func apiSourceAutoSelectsFastestReachableSourceWithSpeechModel() throws {
        let sgp = MimoConfigSource(
            id: "sgp",
            baseURL: try #require(URL(string: "https://sgp.example.test")),
            apiKey: "sgp-secret"
        )
        let cn = MimoConfigSource(
            id: "cn",
            baseURL: try #require(URL(string: "https://cn.example.test")),
            apiKey: "cn-secret"
        )
        let failed = MimoConfigSource(
            id: "failed",
            baseURL: try #require(URL(string: "https://failed.example.test")),
            apiKey: "bad-secret"
        )
        let measurements = [
            "sgp": SourceLatencyMeasurement(
                milliseconds: 220,
                httpStatus: 200,
                reachable: true,
                allowedModelIDs: ["mimo-v2-omni"]
            ),
            "cn": SourceLatencyMeasurement(
                milliseconds: 80,
                httpStatus: 200,
                reachable: true,
                allowedModelIDs: ["mimo-v2.5"]
            ),
            "failed": SourceLatencyMeasurement(
                milliseconds: 20,
                httpStatus: 401,
                reachable: false,
                allowedModelIDs: []
            )
        ]
        let resolved = APISourceResolver.resolvedSource(
            activeSourceID: MimoConfig.autoSourceID,
            sources: [failed, sgp, cn],
            latencyResults: measurements
        )
        #expect(resolved?.id == "cn")
        #expect(APISourceResolver.resolvedSource(
            activeSourceID: MimoConfig.autoSourceID,
            sources: [sgp, cn],
            latencyResults: [:]
        )?.id == "sgp")
    }
    @Test
    func baseURLNormalizationAndRedaction() {
        #expect(MimoConfig.normalizedBaseURL(from: "https://token-plan-sgp.xiaomimimo.com/v1/")?.absoluteString == "https://token-plan-sgp.xiaomimimo.com")
        #expect(MimoConfig.normalizedBaseURL(from: "https://example.test/custom/v1")?.absoluteString == "https://example.test/custom")
        #expect(MimoConfig.normalizedBaseURL(from: "not a url") == nil)
        #expect(MimoConfig.redactedAPIKey("sk-abcdefghijklmnopqrstuvwxyz") == "sk-ab…wxyz")
    }
    @Test
    func uiLanguageMigratesFromLegacyLanguageAndPersists() {
        let suiteName = "omnivoice-ui-language-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(LanguagePreference.english.rawValue, forKey: SettingsStore.Key.language)

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.uiLanguage == .english)
        settings.uiLanguage = .chinese
        #expect(settings.uiLanguage == .chinese)
        #expect(settings.hudMessageDuration == .seconds3)
        settings.hudMessageDuration = .seconds8
        #expect(settings.hudMessageDuration == .seconds8)
        #expect(settings.minRecordingDuration == .milliseconds500)
        settings.minRecordingDuration = .seconds2
        #expect(settings.minRecordingDuration == .seconds2)
    }
}
