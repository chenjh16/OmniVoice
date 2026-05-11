import Foundation

extension UIStrings {
    func configurationTitle(_ config: MimoConfig) -> String {
        let status: String
        if config.apiKey?.nilIfBlank == nil {
            status = language == .chinese ? "缺少 API Key" : "Missing API Key"
        } else if !config.warnings.isEmpty {
            status = language == .chinese ? "需检查" : "Check needed"
        } else {
            status = language == .chinese ? "有效" : "Ready"
        }
        let source = config.activeSourceID
        return language == .chinese
            ? "配置：\(status) · \(source)"
            : "Configuration: \(status) · \(source)"
    }

    func apiKeyStatus(_ config: MimoConfig) -> String {
        config.apiKey?.nilIfBlank == nil
            ? missing
            : config.redactedStatus.apiKeyPreview
    }

    func configWarning(_ warning: String) -> String {
        ConfigWarning.localized(warning, language: language)
    }

    func apiSourceTitle(_ config: MimoConfig, mode: TranscriptionPipelineMode = .defaultMode) -> String {
        if mode == .systemASROnly {
            return language == .chinese ? "API 来源：仅系统 ASR" : "API Source: System ASR Only"
        }
        let label = config.activeSourceID == MimoConfig.autoSourceID
            ? (language == .chinese ? "自动" : "Auto")
            : config.activeSourceID
        return language == .chinese
            ? "API 来源：\(label)"
            : "API Source: \(label)"
    }

    func autoAPISourceMenuItem(resolvedSourceID: String) -> String {
        language == .chinese
            ? "自动（选择最快可用来源） · 当前 \(resolvedSourceID)"
            : "Auto (fastest available source) · current \(resolvedSourceID)"
    }

    func apiSourceMenuItem(_ source: ConfigSourceSummary, latency: SourceLatencyMeasurement?) -> String {
        let status = source.apiKeyConfigured ? configured : missing
        let latencyText: String
        if let latency, let milliseconds = latency.milliseconds {
            let modelText = latency.hasAllowedSpeechModel
                ? (language == .chinese ? "模型可用" : "models OK")
                : (language == .chinese ? "无可用模型" : "no speech model")
            latencyText = latency.reachable
                ? "\(milliseconds)ms · \(modelText)"
                : "\(milliseconds)ms · \(latency.httpStatus.map(String.init) ?? "failed")"
        } else if let latency {
            latencyText = latency.errorKind ?? (language == .chinese ? "失败" : "failed")
        } else {
            latencyText = language == .chinese ? "未测速" : "not measured"
        }
        return "\(source.id) · \(source.host) · \(status) · \(latencyText)"
    }

    func latencyIntervalTitle(_ interval: ConfigLatencyInterval) -> String {
        language == .chinese
            ? "测速频率：\(latencyIntervalLabel(interval))"
            : "Latency Check: \(latencyIntervalLabel(interval))"
    }

    func latencyIntervalLabel(_ interval: ConfigLatencyInterval) -> String {
        switch (language, interval) {
        case (.chinese, .off): return "关闭"
        case (.english, .off): return "Off"
        case (.chinese, .startupOnly): return "仅启动时"
        case (.english, .startupOnly): return "Startup only"
        case (.chinese, .seconds30): return "每 30 秒"
        case (.english, .seconds30): return "Every 30 seconds"
        case (.chinese, .minutes1): return "每 1 分钟"
        case (.english, .minutes1): return "Every 1 minute"
        case (.chinese, .minutes2): return "每 2 分钟"
        case (.english, .minutes2): return "Every 2 minutes"
        case (.chinese, .minutes5): return "每 5 分钟"
        case (.english, .minutes5): return "Every 5 minutes"
        case (.chinese, .minutes15): return "每 15 分钟"
        case (.english, .minutes15): return "Every 15 minutes"
        case (.chinese, .minutes30): return "每 30 分钟"
        case (.english, .minutes30): return "Every 30 minutes"
        case (.chinese, .minutes60): return "每 60 分钟"
        case (.english, .minutes60): return "Every 60 minutes"
        }
    }
}
