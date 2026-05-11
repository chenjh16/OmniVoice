import AppKit
import Foundation

extension AppCoordinator {
    func startSystemASRRuntimeRecoveryMonitoring() {
        guard systemASRRuntimeRecoveryObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        systemASRRuntimeRecoveryObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemASRRuntimeEvent(.willSleep) }
            }
        )
        systemASRRuntimeRecoveryObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemASRRuntimeEvent(.didWake) }
            }
        )
        systemASRRuntimeRecoveryObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemASRRuntimeEvent(.screensDidSleep) }
            }
        )
        systemASRRuntimeRecoveryObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemASRRuntimeEvent(.screensDidWake) }
            }
        )

        let distributedCenter = DistributedNotificationCenter.default()
        systemASRRuntimeRecoveryObservers.append(
            distributedCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemASRRuntimeEvent(.screenLocked) }
            }
        )
        systemASRRuntimeRecoveryObservers.append(
            distributedCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemASRRuntimeEvent(.screenUnlocked) }
            }
        )
    }

    func stopSystemASRRuntimeRecoveryMonitoring() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()
        for observer in systemASRRuntimeRecoveryObservers {
            workspaceCenter.removeObserver(observer)
            distributedCenter.removeObserver(observer)
        }
        systemASRRuntimeRecoveryObservers.removeAll(keepingCapacity: false)
        cancelSpeechAnalyzerRecoveryProbe()
    }

    func handleSystemASRRuntimeEvent(_ event: SystemASRRuntimeRecoveryEvent) {
        resetSystemASRRuntime(event: event)
        switch event {
        case .didWake, .screensDidWake, .screenUnlocked:
            enterSpeechAnalyzerRecoveryCooldown(event: event)
            scheduleSpeechAnalyzerRecoveryProbe(event: event)
        case .willSleep, .screensDidSleep, .screenLocked:
            cancelSpeechAnalyzerRecoveryProbe()
        case .speechAnalyzerStartFailed, .speechAnalyzerProbeFailed:
            enterSpeechAnalyzerRecoveryCooldown(event: event)
            scheduleSpeechAnalyzerRecoveryProbe(event: event)
        }
    }

    func resetSystemASRRuntime(event: SystemASRRuntimeRecoveryEvent) {
        speechAnalyzerRecoveryGeneration += 1
        cancelLiveASRSession()
        pendingTranscription?.liveASRFinalTask?.cancel()
        recordLocalDiagnostic(
            stage: "system_asr_runtime_reset",
            details: [
                "event": event.rawValue,
                "state": String(describing: state),
                "configured_engine": settings.systemASREngine.rawValue,
                "effective_engine": effectiveSystemASREngine.rawValue
            ]
        )
    }

    func enterSpeechAnalyzerRecoveryCooldown(event: SystemASRRuntimeRecoveryEvent) {
        guard let cooldownUntil = SystemASRRuntimeRecoveryPlanner.cooldownUntil(
            event: event,
            now: Date()
        ) else {
            return
        }
        speechAnalyzerRecoveryCooldownUntil = max(speechAnalyzerRecoveryCooldownUntil ?? cooldownUntil, cooldownUntil)
        recordLocalDiagnostic(
            stage: "speech_analyzer_recovery_cooldown",
            details: [
                "event": event.rawValue,
                "configured_engine": settings.systemASREngine.rawValue,
                "effective_engine": effectiveSystemASREngine.rawValue,
                "live_engine": effectiveLiveASREngine.rawValue,
                "cooldown_until": iso8601String(speechAnalyzerRecoveryCooldownUntil)
            ]
        )
    }

    func markSpeechAnalyzerLiveStartFailedForRecovery() {
        enterSpeechAnalyzerRecoveryCooldown(event: .speechAnalyzerStartFailed)
        scheduleSpeechAnalyzerRecoveryProbe(event: .speechAnalyzerStartFailed)
    }

    func scheduleSpeechAnalyzerRecoveryProbe(event: SystemASRRuntimeRecoveryEvent) {
        guard SystemASRRuntimeRecoveryPlanner.shouldScheduleSpeechAnalyzerProbe(
            configured: effectiveSystemASREngine,
            speechAnalyzerAvailable: speechAnalyzerAvailable
        ) else {
            return
        }
        cancelSpeechAnalyzerRecoveryProbe()
        let generation = speechAnalyzerRecoveryGeneration + 1
        speechAnalyzerRecoveryGeneration = generation
        let delayNanoseconds = UInt64(SystemASRRuntimeRecoveryPlanner.probeDelaySeconds * 1_000_000_000)
        speechAnalyzerRecoveryProbeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            await self?.runSpeechAnalyzerRecoveryProbe(event: event, generation: generation)
        }
    }

    func cancelSpeechAnalyzerRecoveryProbe() {
        speechAnalyzerRecoveryProbeTask?.cancel()
        speechAnalyzerRecoveryProbeTask = nil
    }

    func runSpeechAnalyzerRecoveryProbe(
        event: SystemASRRuntimeRecoveryEvent,
        generation: Int
    ) async {
        guard generation == speechAnalyzerRecoveryGeneration,
              state == .idle,
              effectiveSystemASREngine == .speechAnalyzer,
              speechAnalyzerAvailable else {
            return
        }
        let options = SystemSpeechRecognitionOptions(
            language: .defaultLanguage,
            engine: .speechAnalyzer,
            keywordHints: currentSystemASRKeywordHintsContext
        )
        do {
            let session = try await systemSpeechRecognizer.makeLiveSession(
                options: options,
                onUpdate: { _ in }
            )
            session.cancel()
            guard generation == speechAnalyzerRecoveryGeneration else { return }
            speechAnalyzerRecoveryCooldownUntil = nil
            speechAnalyzerRecoveryProbeTask = nil
            recordLocalDiagnostic(
                stage: "speech_analyzer_recovery_probe_succeeded",
                details: [
                    "event": event.rawValue,
                    "configured_engine": settings.systemASREngine.rawValue
                ]
            )
        } catch {
            guard generation == speechAnalyzerRecoveryGeneration else { return }
            speechAnalyzerRecoveryProbeTask = nil
            enterSpeechAnalyzerRecoveryCooldown(event: .speechAnalyzerProbeFailed)
            recordLocalDiagnostic(
                stage: "speech_analyzer_recovery_probe_failed",
                errorKind: diagnosticKind(for: error),
                details: [
                    "event": event.rawValue,
                    "configured_engine": settings.systemASREngine.rawValue,
                    "cooldown_until": iso8601String(speechAnalyzerRecoveryCooldownUntil)
                ]
            )
        }
    }

    func iso8601String(_ date: Date?) -> String {
        guard let date else { return "none" }
        return ISO8601DateFormatter().string(from: date)
    }
}
