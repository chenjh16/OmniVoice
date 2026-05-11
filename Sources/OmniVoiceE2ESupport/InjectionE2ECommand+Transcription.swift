import Foundation
import OmniVoiceCore

extension InjectionE2ECommand {
    @MainActor
    static func transcriptText(parser: InjectionE2EArgumentParser) async throws -> String {
        guard let wavPath = parser.value(after: "--fixture-wav")?.nilIfBlank else {
            throw InjectionE2ECommandError.missingTranscriptInput
        }
        let wavURL = URL(fileURLWithPath: wavPath)
        guard let wavData = try? Data(contentsOf: wavURL) else {
            throw InjectionE2ECommandError.fixtureWAVReadFailed
        }
        guard WAVEncoder.validatePCM16Mono16kWAV(wavData) else {
            throw InjectionE2ECommandError.invalidFixtureWAV
        }

        let loader = configLoader(parser: parser)
        let config = AppConfigStore(loader: loader).config.resolvingSource(using: [:])
        let model = parser.value(after: "--model").flatMap(AllowedSpeechModel.init(rawValue:))
            ?? config.modelCatalogs.inputAudioDefaultModel
        let selection = TranscriptionStyleSelection(
            rawValue: parser.value(after: "--style") ?? config.preferences.transcriptionStyleSelection.rawValue
        )
        let descriptor = TranscriptionStyleResolver.resolve(
            selection: selection,
            customStyles: config.customStyles
        )
        let enabledIDs = Set(config.preferences.enabledKeywordGroupIDs)
        let keywordHints = KeywordHintsContext(
            isEnabled: config.preferences.keywordHintsEnabled,
            groups: config.keywordGroups.filter { enabledIDs.contains($0.id) }
        )
        let instruction = TranscriptionInstructionBuilder.instruction(
            descriptor: descriptor,
            keywordHints: keywordHints
        )
        let client = MimoAPIClient(config: config)
        return try await client.transcribe(
            wavData: wavData,
            model: model,
            instruction: instruction,
            onDelta: { _ in }
        )
    }
}
