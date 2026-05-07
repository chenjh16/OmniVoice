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
          "preferences": {
            "ui_language": "en",
            "transcription_style": "rewrite",
            "keyword_hints_enabled": true,
            "enabled_keyword_groups": ["omnivoice_terms", "bad group"],
            "trigger_key": "modifier-left-control",
            "min_recording_duration_ms": 800,
            "max_recording_duration_seconds": 120,
            "auto_insert": false,
            "launch_at_login": true,
            "hud": {
              "visual_style": "lightCapsule",
              "message_duration_seconds": 5,
              "reveal_delay_ms": 400,
            },
          },
          "custom_styles": {
            "support_reply": {
              "display_name_zh": "客服回复",
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
          "keyword_groups": {
            "omnivoice_terms": {
              "display_name": "OmniVoice 术语",
              "description": "项目和 API 相关术语。",
              "keywords": [
                " OmniVoice ",
                "MiMo",
                "mimo-v2-omni",
                "MiMo",
                "",
                "bad\\nkeyword"
              ],
            },
            "bad group": {
              "display_name": "Bad",
              "keywords": ["ignored"]
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
        #expect(config.preferences.uiLanguage == .english)
        #expect(config.preferences.transcriptionStyleSelection.rawValue == "rewrite")
        #expect(config.preferences.keywordHintsEnabled)
        #expect(config.preferences.enabledKeywordGroupIDs == ["omnivoice_terms"])
        #expect(config.preferences.triggerKey == .leftControl)
        #expect(config.preferences.minRecordingDuration == .milliseconds800)
        #expect(config.preferences.maxRecordingDuration == .seconds120)
        #expect(config.preferences.autoInsert == false)
        #expect(config.preferences.launchAtLogin == true)
        #expect(config.preferences.hudVisualStyle == .lightCapsule)
        #expect(config.preferences.hudMessageDuration == .seconds5)
        #expect(config.preferences.hudRevealDelay == .milliseconds400)
        #expect(config.customStyles.count == 1)
        #expect(config.customStyles.first?.id == "support_reply")
        #expect(config.customStyles.first?.displayNameZH == "客服回复")
        #expect(config.customStyles.first?.displayName == "客服回复")
        #expect(config.customStyles.first?.localizedDescription(in: .english) == "简短客服回复")
        #expect(config.customStyles.first?.prompt.contains("refund amounts") == true)
        #expect(config.keywordGroups.count == 1)
        let keywordGroup = try #require(config.keywordGroups.first)
        #expect(keywordGroup.id == "omnivoice_terms")
        #expect(keywordGroup.localizedName(in: .english) == "OmniVoice 术语")
        #expect(keywordGroup.localizedName(in: .chinese) == "OmniVoice 术语")
        #expect(keywordGroup.keywords == ["OmniVoice", "MiMo", "mimo-v2-omni"])
        #expect(config.warnings.contains("Config warning: invalid keyword groups ignored"))
        #expect(config.warnings.contains("Config warning: invalid keywords ignored"))
        #expect(config.redactedStatus.baseURLHost == "cn.example.test")
        #expect(config.redactedStatus.apiKeyConfigured)
        #expect(config.redactedStatus.apiKeyPreview == "••••••")
        #expect(!config.redactedStatus.displayLines.joined().contains("cn-secret"))
    }
    @Test
    func configLoaderBacksUpAndRebuildsIncompleteConfig() throws {
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

        let loader = ConfigLoader(configFileURL: jsoncURL)
        let rebuilt = loader.ensureValidConfig(uiLanguage: .chinese)
        #expect(rebuilt.source == .configFile)
        #expect(rebuilt.activeSourceID == MimoConfig.autoSourceID)
        #expect(rebuilt.resolvedSourceID == "config1")
        #expect(rebuilt.apiKey == nil)
        #expect(rebuilt.preferences.uiLanguage == .chinese)
        #expect(rebuilt.preferences.hudRevealDelay == .milliseconds200)
        #expect(rebuilt.customStyles.first?.id == "meeting_notes")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("config.jsonc.bak-") }
        #expect(backups.count == 1)

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
    func ensureValidConfigRebuildsBadJSONEmptySourcesAndInvalidPreferences() throws {
        let cases = [
            ("bad-json", "{ nope"),
            ("empty-sources", """
            {
              "active_source": "auto",
              "default_model": "mimo-v2-omni",
              "sources": {},
              "latency": { "enabled": true, "interval_seconds": 1800 },
              "preferences": {
                "ui_language": "en",
                "transcription_style": "concise",
                "trigger_key": "fn-globe",
                "min_recording_duration_ms": 500,
                "max_recording_duration_seconds": 60,
                "auto_insert": true,
                "launch_at_login": false,
                "hud": {
                  "visual_style": "automatic",
                  "message_duration_seconds": 3,
                  "reveal_delay_ms": 200
                }
              }
            }
            """),
            ("bad-preferences", """
            {
              "active_source": "config1",
              "default_model": "mimo-v2-omni",
              "sources": {
                "config1": {
                  "base_url": "https://example.test",
                  "api_key": ""
                }
              },
              "latency": { "enabled": true, "interval_seconds": 1800 },
              "preferences": {
                "ui_language": "en",
                "transcription_style": "concise",
                "trigger_key": "fn-globe",
                "min_recording_duration_ms": 500,
                "max_recording_duration_seconds": 60,
                "auto_insert": true,
                "launch_at_login": false,
                "hud": {
                  "visual_style": "automatic",
                  "message_duration_seconds": 3,
                  "reveal_delay_ms": 999
                }
              }
            }
            """)
        ]

        for (name, text) in cases {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("omnivoice-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configURL = directory.appendingPathComponent("config.jsonc")
            try Data(text.utf8).write(to: configURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

            let rebuilt = ConfigLoader(configFileURL: configURL).ensureValidConfig(uiLanguage: .english)
            #expect(rebuilt.source == .configFile)
            #expect(rebuilt.resolvedSourceID == "config1")
            #expect(rebuilt.preferences.uiLanguage == .english)
            #expect(rebuilt.preferences.hudRevealDelay == .milliseconds200)
            let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix("config.jsonc.bak-") }
            #expect(backups.count == 1)
        }
    }
    @Test
    func configMenuStateWritesAnnotatedJSONCAndPreservesSupportedFields() throws {
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
          "latency": {
            "enabled": true,
            "interval_seconds": 1800
          },
          "preferences": {
            "ui_language": "zh-Hans",
            "transcription_style": "concise",
            "keyword_hints_enabled": true,
            "enabled_keyword_groups": ["meeting_terms"],
            "trigger_key": "fn-globe",
            "min_recording_duration_ms": 500,
            "max_recording_duration_seconds": 60,
            "auto_insert": true,
            "launch_at_login": false,
            "hud": {
              "visual_style": "automatic",
              "message_duration_seconds": 3,
              "reveal_delay_ms": 200
            }
          },
          "custom_styles": {
            "meeting_notes": {
              "display_name": "Meeting Notes",
              "prompt": "Keep action items."
            }
          },
          "keyword_groups": {
            "meeting_terms": {
              "display_name": "Meeting Terms",
              "keywords": ["OmniVoice", "MiMo"]
            }
          }
        }
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)

        let loader = ConfigLoader(configFileURL: configURL)
        #expect(loader.saveActiveSource("backup"))
        #expect(loader.saveLatencyInterval(.startupOnly))
        let preferences = ConfigPreferences(
            selectedModel: .mimoV2Omni,
            uiLanguage: .english,
            transcriptionStyleSelection: .builtIn(.rewrite),
            keywordHintsEnabled: false,
            enabledKeywordGroupIDs: ["meeting_terms"],
            triggerKey: .leftControl,
            minRecordingDuration: .milliseconds300,
            maxRecordingDuration: .seconds15,
            autoInsert: false,
            launchAtLogin: true,
            hudVisualStyle: .darkCapsule,
            hudMessageDuration: .seconds12,
            hudRevealDelay: .milliseconds500
        )
        #expect(loader.savePreferences(preferences))

        let data = try Data(contentsOf: configURL)
        let raw = try #require(String(data: data, encoding: .utf8))
        #expect(raw.contains("OmniVoice reads this file"))
        #expect(raw.contains("HUD visual style"))
        let object = try jsoncObject(from: configURL)
        #expect(object["default_model"] as? String == "mimo-v2-omni")
        #expect(object["custom_flag"] == nil)
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
        let promptLines = try #require(meetingNotes["prompt_lines"] as? [String])
        #expect(promptLines.joined(separator: "\n") == "Keep action items.")
        let latency = try #require(object["latency"] as? [String: Any])
        #expect(latency["enabled"] as? Bool == true)
        #expect(latency["interval_seconds"] is NSNull)
        let savedPreferences = try #require(object["preferences"] as? [String: Any])
        #expect(savedPreferences["ui_language"] as? String == "en")
        #expect(savedPreferences["transcription_style"] as? String == "rewrite")
        #expect(savedPreferences["keyword_hints_enabled"] as? Bool == false)
        #expect(savedPreferences["enabled_keyword_groups"] as? [String] == ["meeting_terms"])
        #expect(savedPreferences["trigger_key"] as? String == "modifier-left-control")
        #expect(savedPreferences["min_recording_duration_ms"] as? Int == 300)
        #expect(savedPreferences["max_recording_duration_seconds"] as? Int == 15)
        #expect(savedPreferences["auto_insert"] as? Bool == false)
        #expect(savedPreferences["launch_at_login"] as? Bool == true)
        let hud = try #require(savedPreferences["hud"] as? [String: Any])
        #expect(hud["visual_style"] as? String == "darkCapsule")
        #expect(hud["message_duration_seconds"] as? Int == 12)
        #expect(hud["reveal_delay_ms"] as? Int == 500)
        let keywordGroups = try #require(object["keyword_groups"] as? [String: Any])
        let meetingTerms = try #require(keywordGroups["meeting_terms"] as? [String: Any])
        #expect(meetingTerms["display_name"] as? String == "Meeting Terms")
        #expect(meetingTerms["keywords"] as? [String] == ["OmniVoice", "MiMo"])
        let permissions = try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber
        #expect((permissions?.intValue ?? 0) & 0o777 == 0o600)
    }
    @Test
    func configWriterRewritesCommentLanguageFromPreferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-comment-language-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        let loader = ConfigLoader(configFileURL: configURL)
        _ = loader.ensureValidConfig(uiLanguage: .chinese)
        var preferences = ConfigPreferences.defaultPreferences(selectedModel: .defaultModel, uiLanguage: .english)
        #expect(loader.savePreferences(preferences))
        var raw = try String(contentsOf: configURL, encoding: .utf8)
        #expect(raw.contains("OmniVoice reads this file"))
        #expect(!raw.contains("OmniVoice 会读取"))

        preferences = preferences.with(uiLanguage: .chinese)
        #expect(loader.savePreferences(preferences))
        raw = try String(contentsOf: configURL, encoding: .utf8)
        #expect(raw.contains("OmniVoice 会读取"))
        #expect(!raw.contains("OmniVoice reads this file"))
    }
    @Test
    func configValidationLoadAndSnapshotExportSupportHotReloadFallback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-hot-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        let loader = ConfigLoader(configFileURL: configURL)

        try Data("{ nope".utf8).write(to: configURL)
        #expect(loader.loadValidConfigWithoutRepair() == .invalid(["unreadable"]))

        let valid = ConfigTemplateBuilder.template(uiLanguage: .english)
        try Data(valid.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        let loaded: MimoConfig
        switch loader.loadValidConfigWithoutRepair() {
        case .valid(let config):
            loaded = config
        case .invalid(let issues):
            Issue.record("Expected valid config, got \(issues)")
            return
        }

        let exportURL = try #require(loader.exportCurrentConfigSnapshot(
            loaded,
            uiLanguage: .english,
            now: Date(timeIntervalSince1970: 1_777_777_777)
        ))
        #expect(exportURL.lastPathComponent.hasPrefix("config.current-"))
        #expect(exportURL.lastPathComponent.hasSuffix(".jsonc"))
        let exported = try jsoncObject(from: exportURL)
        #expect(exported["keyword_groups"] is [String: Any])
        let permissions = try FileManager.default.attributesOfItem(atPath: exportURL.path)[.posixPermissions] as? NSNumber
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
        #expect(chineseTemplate.contains(#""preferences""#))
        #expect(chineseTemplate.contains(#""reveal_delay_ms": 200"#))
        #expect(chineseTemplate.contains(#""custom_styles""#))
        #expect(chineseTemplate.contains(#""keyword_groups""#))
        #expect(chineseTemplate.contains(#""keyword_hints_enabled": true"#))
        #expect(chineseTemplate.contains(#""enabled_keyword_groups": ["omnivoice_terms", "technical_terms"]"#))
        #expect(chineseTemplate.contains("OmniVoice 术语"))
        #expect(chineseTemplate.contains("技术术语"))
        #expect(chineseTemplate.contains("HUD"))
        #expect(chineseTemplate.contains("Fn"))
        #expect(chineseTemplate.contains("自定义转写风格"))
        #expect(chineseTemplate.contains("OmniVoice 会读取"))
        let englishTemplate = ConfigTemplateBuilder.template(uiLanguage: .english)
        #expect(englishTemplate.contains("OmniVoice reads this file"))
        #expect(englishTemplate.contains(#""sources""#))
        #expect(englishTemplate.contains("Delay before the listening HUD appears"))
        #expect(englishTemplate.contains("Custom transcription styles"))
        #expect(englishTemplate.contains("Keyword groups"))
        #expect(englishTemplate.contains(#""enabled_keyword_groups": ["omnivoice_terms", "technical_terms"]"#))
        #expect(englishTemplate.contains("Technical Terms"))

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
        let preferences = try #require(object["preferences"] as? [String: Any])
        #expect(preferences["ui_language"] as? String == "en")
        #expect(preferences["keyword_hints_enabled"] as? Bool == true)
        #expect(preferences["enabled_keyword_groups"] as? [String] == ["omnivoice_terms", "technical_terms"])
        let keywordGroups = try #require(object["keyword_groups"] as? [String: Any])
        #expect(keywordGroups.keys.sorted() == ["omnivoice_terms", "technical_terms"])
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
        #expect(settings.hudRevealDelay == .milliseconds200)
        settings.hudRevealDelay = .milliseconds100
        #expect(settings.hudRevealDelay == .milliseconds100)
    }

    private func jsoncObject(from url: URL) throws -> [String: Any] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let data = try #require(JSONCNormalizer.normalize(raw).data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
