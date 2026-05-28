import Foundation
import Testing
@testable import OmniVoiceCore

@Suite("External ASR plugins")
struct ExternalASRTests {
    @Test
    func registryDiscoversValidASRPluginManifest() throws {
        let root = try makeTemporaryPluginRoot()
        let pluginDirectory = root.appendingPathComponent("acme-asr", isDirectory: true)
        try FileManager.default.createDirectory(
            at: pluginDirectory.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        let helper = pluginDirectory.appendingPathComponent("bin/acme-asr-helper")
        try Data().write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        try writeManifest(
            """
            {
              "id": "acme-asr",
              "name": "Acme ASR",
              "version": "1.0.0",
              "type": "asr_provider",
              "entry": "bin/acme-asr-helper",
              "protocol": "omnivoice-asr-jsonl-v1",
              "capabilities": {
                "streaming": true,
                "setup": true
              }
            }
            """,
            to: pluginDirectory
        )

        let plugins = ExternalASRPluginRegistry(pluginRoots: [root]).discoverPlugins()

        let plugin = try #require(plugins.first)
        #expect(plugin.id == "acme-asr")
        #expect(plugin.displayName == "Acme ASR")
        #expect(plugin.version == "1.0.0")
        #expect(plugin.executableURL == helper)
        #expect(plugin.supportsStreaming)
        #expect(plugin.supportsSetup)
    }

    @Test
    func registryIgnoresInvalidPluginManifestsAndSortsByName() throws {
        let root = try makeTemporaryPluginRoot()
        try makePlugin(
            id: "zeta-asr",
            name: "Zeta ASR",
            root: root
        )
        try makePlugin(
            id: "alpha-asr",
            name: "Alpha ASR",
            root: root
        )
        try makePlugin(
            id: "../bad",
            name: "Bad ASR",
            root: root
        )
        let malformed = root.appendingPathComponent("malformed", isDirectory: true)
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try writeManifest(#"{ "id": "bad-json" "#, to: malformed)

        let plugins = ExternalASRPluginRegistry(pluginRoots: [root]).discoverPlugins()

        #expect(plugins.map(\.id) == ["alpha-asr", "zeta-asr"])
        #expect(plugins.map(\.displayName) == ["Alpha ASR", "Zeta ASR"])
    }

    @Test
    func registryRejectsNonExecutableManifestEntry() throws {
        let root = try makeTemporaryPluginRoot()
        let pluginDirectory = root.appendingPathComponent("quiet-asr", isDirectory: true)
        try FileManager.default.createDirectory(
            at: pluginDirectory.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        let helper = pluginDirectory.appendingPathComponent("bin/helper")
        try Data().write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: helper.path)
        try writeManifest(
            """
            {
              "id": "quiet-asr",
              "name": "Quiet ASR",
              "version": "1.0.0",
              "type": "asr_provider",
              "entry": "bin/helper",
              "protocol": "omnivoice-asr-jsonl-v1"
            }
            """,
            to: pluginDirectory
        )

        let plugins = ExternalASRPluginRegistry(pluginRoots: [root]).discoverPlugins()

        #expect(plugins.isEmpty)
    }

    @Test
    func registryRejectsManifestEntryEscapingThroughSymlink() throws {
        let root = try makeTemporaryPluginRoot()
        let pluginDirectory = root.appendingPathComponent("linked-asr", isDirectory: true)
        let outsideDirectory = root.appendingPathComponent("outside-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let escapedHelper = outsideDirectory.appendingPathComponent("helper")
        try Data().write(to: escapedHelper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: escapedHelper.path)
        try FileManager.default.createSymbolicLink(
            at: pluginDirectory.appendingPathComponent("bin"),
            withDestinationURL: outsideDirectory
        )
        try writeManifest(
            """
            {
              "id": "linked-asr",
              "name": "Linked ASR",
              "version": "1.0.0",
              "type": "asr_provider",
              "entry": "bin/helper",
              "protocol": "omnivoice-asr-jsonl-v1"
            }
            """,
            to: pluginDirectory
        )

        let plugins = ExternalASRPluginRegistry(pluginRoots: [root]).discoverPlugins()

        #expect(plugins.isEmpty)
    }

    @Test
    func configLoaderParsesExternalASRProviderSelection() throws {
        let fixture = try ConfigTestFixture(slug: "external-asr-config")
        try fixture.write("""
        {
          "transcription_pipeline": { "mode": "system_asr_only" },
          "system_asr": {
            "engine": "external_asr",
            "keyword_hints_enabled": false,
            "external_asr": {
              "provider_id": "acme-asr"
            }
          },
          "preferences": {
            "ui_language": "en",
            "trigger_key": "fn-globe",
            "min_recording_duration_ms": 500,
            "max_recording_duration_seconds": 120,
            "auto_insert": true,
            "launch_at_login": false,
            "hud": {
              "visual_style": "automatic",
              "message_duration_seconds": 3,
              "reveal_delay_ms": 100,
              "live_asr_preview_enabled": true
            }
          }
        }
        """)

        let loaded = fixture.loader.load()

        #expect(loaded.pipelineMode == .systemASROnly)
        #expect(loaded.systemASRSettings.engine == .externalASR)
        #expect(loaded.systemASRSettings.keywordHintsEnabled == false)
        #expect(loaded.systemASRSettings.externalASR.providerID == "acme-asr")
    }

    @Test
    func externalASRMenuEntriesComeOnlyFromInstalledPlugins() throws {
        let plugin = makeExternalASRPlugin(id: "acme-asr", displayName: "Acme ASR")

        let builtInEntries = SystemASREngineMenuPlanner.entries(
            installedPlugins: [],
            selectedEngine: .classicSpeech,
            selectedExternalProviderID: nil,
            speechAnalyzerAvailable: true,
            uiLanguage: .english
        )
        #expect(builtInEntries.map(\.title) == [
            "SpeechAnalyzer",
            "Classic Speech",
            "Apple Online Speech"
        ])

        let pluginEntries = SystemASREngineMenuPlanner.entries(
            installedPlugins: [plugin],
            selectedEngine: .externalASR,
            selectedExternalProviderID: "acme-asr",
            speechAnalyzerAvailable: true,
            uiLanguage: .english
        )
        #expect(pluginEntries.map(\.title) == [
            "SpeechAnalyzer",
            "Classic Speech",
            "Apple Online Speech",
            "Acme ASR"
        ])
        let pluginEntry = try #require(pluginEntries.first { $0.title == "Acme ASR" })
        #expect(pluginEntry.selection == .externalASRProvider(id: "acme-asr"))
        #expect(pluginEntry.isSelected)
        #expect(pluginEntry.isEnabled)
    }

    @Test
    func externalASRSelectionPlannerSelectsInstalledProvider() {
        let plugin = makeExternalASRPlugin(id: "acme-asr", displayName: "Acme ASR")
        let current = SystemASRSettings(engine: .classicSpeech, keywordHintsEnabled: false)

        let selected = ExternalASRSelectionPlanner.settings(
            selectingProviderID: "acme-asr",
            installedPlugins: [plugin],
            current: current
        )

        #expect(selected == SystemASRSettings(
            engine: .externalASR,
            keywordHintsEnabled: false,
            externalASR: ExternalASRSettings(providerID: "acme-asr")
        ))
        #expect(ExternalASRSelectionPlanner.settings(
            selectingProviderID: "missing-asr",
            installedPlugins: [plugin],
            current: current
        ) == nil)
    }

    @Test
    func jsonlProtocolEncodesRequestsAndParsesResponses() throws {
        let start = try jsonObject(from: ExternalASRProtocol.startRequest(streaming: true))
        #expect(start["type"] as? String == "start")
        #expect(start["sample_rate"] as? Int == 16_000)
        #expect(start["channels"] as? Int == 1)
        #expect(start["streaming"] as? Bool == true)

        let pcm16 = Data([0, 1, 2, 3])
        let audio = try jsonObject(from: ExternalASRProtocol.audioRequest(pcm16: pcm16))
        #expect(audio["type"] as? String == "audio")
        #expect(audio["pcm16"] as? String == pcm16.base64EncodedString())

        let finish = try jsonObject(from: ExternalASRProtocol.finishRequest())
        #expect(finish["type"] as? String == "finish")

        #expect(try ExternalASRProtocol.response(fromLine: #"{"type":"ready"}"#) == .ready)
        #expect(try ExternalASRProtocol.response(
            fromLine: #"{"type":"partial","text":"OpenClaw","replace":true}"#
        ) == .partial(text: "OpenClaw", replace: true))
        #expect(try ExternalASRProtocol.response(
            fromLine: #"{"type":"final","text":"OpenClaw ACP Codex"}"#
        ) == .final(text: "OpenClaw ACP Codex"))
        #expect(try ExternalASRProtocol.response(
            fromLine: #"{"type":"error","message":"bad credentials"}"#
        ) == .error(message: "bad credentials"))
    }

    @Test
    func externalASRLiveSessionStreamsAudioAndReplacesPreview() async throws {
        let plugin = try makeFakeExternalASRPlugin()
        let updates = LockedUpdates()
        let session = try await ExternalASRClient(plugin: plugin).makeLiveSession { update in
            updates.append(update)
        }

        session.append(AudioSampleChunk(samples: [0, 0.25, -0.25], sampleRate: 16_000))
        let result = try await session.finish()

        #expect(result.text == "OpenClaw ACP Codex")
        #expect(updates.values.contains(LiveASRUpdate(
            text: "OpenClaw",
            isFinal: false,
            replacesCurrentSegment: true
        )))
        #expect(updates.values.contains(LiveASRUpdate(
            text: "OpenClaw ACP Codex",
            isFinal: true,
            replacesCurrentSegment: true
        )))
    }

    @Test
    func systemSpeechRecognizerUsesExternalASRPluginForFileRecognition() async throws {
        let plugin = try makeFakeExternalASRPlugin()
        let recognizer = SystemSpeechRecognizer()
        let wavData = WAVEncoder.encodePCM16WAV(samples: [0, 0.1, -0.1])

        let result = try await recognizer.recognize(
            wavData: wavData,
            options: SystemSpeechRecognitionOptions(
                language: .defaultLanguage,
                engine: .externalASR,
                keywordHints: KeywordHintsContext(),
                externalASRPlugin: plugin
            )
        )

        #expect(result.text == "OpenClaw ACP Codex")
    }

    @Test
    func externalASRClientTimesOutWhenHelperDoesNotBecomeReady() async throws {
        let plugin = try makeFakeExternalASRPlugin(script: """
        #!/bin/sh
        sleep 2
        """)
        let client = ExternalASRClient(plugin: plugin, readyTimeoutSeconds: 0.1)

        do {
            _ = try await client.makeLiveSession { _ in }
            Issue.record("Expected helper ready timeout")
        } catch let error as SystemSpeechRecognitionError {
            #expect(error == .recognitionFailed("External ASR helper did not become ready before timeout"))
        }
    }

    @Test
    func externalASRClientDrainsHelperStandardError() async throws {
        let plugin = try makeFakeExternalASRPlugin(script: """
        #!/bin/sh
        dd if=/dev/zero bs=65536 count=64 >&2 2>/dev/null
        while IFS= read -r line; do
          case "$line" in
            *start*)
              printf '%s\\n' '{"type":"ready"}'
              ;;
            *finish*)
              printf '%s\\n' '{"type":"final","text":"stderr drained"}'
              exit 0
              ;;
          esac
        done
        """)
        let client = ExternalASRClient(plugin: plugin, readyTimeoutSeconds: 2)

        let result = try await client.recognize(chunks: [])

        #expect(result.text == "stderr drained")
    }
}

private func makeTemporaryPluginRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("omnivoice-external-asr-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makePlugin(
    id: String,
    name: String,
    root: URL
) throws {
    let directoryName = id.replacingOccurrences(of: "/", with: "-")
    let pluginDirectory = root.appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(
        at: pluginDirectory.appendingPathComponent("bin", isDirectory: true),
        withIntermediateDirectories: true
    )
    let helper = pluginDirectory.appendingPathComponent("bin/helper")
    try Data().write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    try writeManifest(
        """
        {
          "id": "\(id)",
          "name": "\(name)",
          "version": "1.0.0",
          "type": "asr_provider",
          "entry": "bin/helper",
          "protocol": "omnivoice-asr-jsonl-v1",
          "capabilities": {
            "streaming": true,
            "setup": false
          }
        }
        """,
        to: pluginDirectory
    )
}

private func writeManifest(_ raw: String, to pluginDirectory: URL) throws {
    try Data(raw.utf8).write(to: pluginDirectory.appendingPathComponent("plugin.json"))
}

private func makeExternalASRPlugin(
    id: String,
    displayName: String,
    executableURL: URL? = nil
) -> ExternalASRPlugin {
    let directory = executableURL?
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-plugin-\(id)", isDirectory: true)
    return ExternalASRPlugin(
        id: id,
        displayName: displayName,
        version: "1.0.0",
        pluginDirectoryURL: directory,
        executableURL: executableURL ?? directory.appendingPathComponent("bin/helper"),
        supportsStreaming: true,
        supportsSetup: false
    )
}

private func makeFakeExternalASRPlugin(script: String = fakeExternalASRHelperScript) throws -> ExternalASRPlugin {
    let root = try makeTemporaryPluginRoot()
    let pluginDirectory = root.appendingPathComponent("fake-asr", isDirectory: true)
    let bin = pluginDirectory.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let helper = bin.appendingPathComponent("fake-helper")
    try Data(script.utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    return makeExternalASRPlugin(
        id: "fake-asr",
        displayName: "Fake ASR",
        executableURL: helper
    )
}

private let fakeExternalASRHelperScript = """
#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *start*)
      printf '%s\\n' '{"type":"ready"}'
      ;;
    *audio*)
      printf '%s\\n' '{"type":"partial","text":"OpenClaw","replace":true}'
      ;;
    *finish*)
      printf '%s\\n' '{"type":"final","text":"OpenClaw ACP Codex"}'
      exit 0
      ;;
  esac
done
"""

private func jsonObject(from data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private final class LockedUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LiveASRUpdate] = []

    var values: [LiveASRUpdate] {
        lock.withLock { storage }
    }

    func append(_ update: LiveASRUpdate) {
        lock.withLock {
            storage.append(update)
        }
    }
}
