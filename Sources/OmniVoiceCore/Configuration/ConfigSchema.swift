import Foundation

enum ConfigSchema {
    enum Root {
        static let activeSource = "active_source"
        static let transcriptionPipeline = "transcription_pipeline"
        static let models = "models"
        static let systemASR = "system_asr"
        static let sources = "sources"
        static let latency = "latency"
        static let preferences = "preferences"
        static let customStyles = "custom_styles"
        static let keywordGroups = "keyword_groups"
        static let deprecatedDefaultModel = "default_model"
    }

    enum Pipeline {
        static let mode = "mode"
    }

    enum Models {
        static let audioLLM = "audio_llm"
        static let legacyInputAudio = "input_audio"
        static let textLLM = "text_llm"
        static let defaultModel = "default_model"
        static let extraModels = "extra_models"

        static let requiredSections = [audioLLM, textLLM]
    }

    enum Source {
        static let baseURL = "base_url"
        static let apiKey = "api_key"
    }

    enum SystemASR {
        static let engine = "engine"
        static let keywordHintsEnabled = "keyword_hints_enabled"
        static let deprecatedAllowAppleServerRecognition = "allow_apple_server_recognition"
    }

    enum Latency {
        static let enabled = "enabled"
        static let intervalSeconds = "interval_seconds"
    }

    enum Preferences {
        static let uiLanguage = "ui_language"
        static let transcriptionStyle = "transcription_style"
        static let keywordHintsEnabled = "keyword_hints_enabled"
        static let enabledKeywordGroups = "enabled_keyword_groups"
        static let triggerKey = "trigger_key"
        static let trigger = "trigger"
        static let minRecordingDurationMS = "min_recording_duration_ms"
        static let maxRecordingDurationSeconds = "max_recording_duration_seconds"
        static let autoInsert = "auto_insert"
        static let launchAtLogin = "launch_at_login"
        static let hud = "hud"
    }

    enum Trigger {
        static let continuousRecordingDoubleTapEnabled = "continuous_recording_double_tap_enabled"
    }

    enum HUD {
        static let visualStyle = "visual_style"
        static let messageDurationSeconds = "message_duration_seconds"
        static let revealDelayMS = "reveal_delay_ms"
        static let liveASRPreviewEnabled = "live_asr_preview_enabled"
    }

    enum CustomStyle {
        static let displayName = "display_name"
        static let prompt = "prompt"
        static let promptLines = "prompt_lines"
    }

    enum KeywordGroup {
        static let displayName = "display_name"
        static let keywords = "keywords"
    }

    static let deprecatedDisplayMetadataKeys = [
        "display_name_zh",
        "description",
        "description_zh"
    ]
}
