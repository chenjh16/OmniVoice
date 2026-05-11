import Foundation
import Testing
@testable import OmniVoiceCore

@Suite("Permission planners")
struct PermissionPlannerTests {
    @Test
    func permissionGuidePlannerRequestsMissingPermissionsOnce() {
        let missingInput = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            speechRecognitionGranted: true
        )
        #expect(PermissionGuidePlanner.actions(
            for: missingInput,
            hasRunStartupGuide: false,
            isManualRequest: false
        ) == [.requestInputMonitoring, .openInputMonitoringSettings])
        #expect(PermissionGuidePlanner.actions(
            for: missingInput,
            hasRunStartupGuide: true,
            isManualRequest: false
        ) == [])
        #expect(PermissionGuidePlanner.actions(
            for: missingInput,
            hasRunStartupGuide: true,
            isManualRequest: true
        ) == [.requestInputMonitoring, .openInputMonitoringSettings])

        let missingAccessibility = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: false,
            inputMonitoringGranted: true,
            speechRecognitionGranted: true
        )
        #expect(PermissionGuidePlanner.actions(
            for: missingAccessibility,
            hasRunStartupGuide: false,
            isManualRequest: false
        ) == [.requestAccessibility])
        #expect(PermissionGuidePlanner.actions(
            for: missingAccessibility,
            hasRunStartupGuide: true,
            isManualRequest: true
        ) == [.requestAccessibility, .openAccessibilitySettings])

        let missingSpeech = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            speechRecognitionGranted: false
        )
        #expect(PermissionGuidePlanner.actions(
            for: missingSpeech,
            hasRunStartupGuide: false,
            isManualRequest: false
        ) == [.requestSpeechRecognition])
        #expect(PermissionGuidePlanner.actions(
            for: missingSpeech,
            hasRunStartupGuide: true,
            isManualRequest: true
        ) == [.requestSpeechRecognition])
    }

    @Test
    func permissionReadinessAutoEnablesOnlyPermissionBlockedStops() {
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        #expect(PermissionReadinessPlanner.shouldAutoEnable(
            previous: missing,
            current: ready,
            stopReason: .permissionBlocked
        ))
        #expect(!PermissionReadinessPlanner.shouldAutoEnable(
            previous: missing,
            current: ready,
            stopReason: .manual
        ))
        #expect(!PermissionReadinessPlanner.shouldAutoEnable(
            previous: missing,
            current: missing,
            stopReason: .permissionBlocked
        ))
        #expect(!PermissionReadinessPlanner.shouldAutoEnable(
            previous: ready,
            current: ready,
            stopReason: .permissionBlocked
        ))
    }

    @Test
    func listeningStartupRequiresPermissionsAndNoOtherInstance() {
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        #expect(PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: ready,
            hasOtherRunningInstance: false
        ))
        #expect(!PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: missing,
            hasOtherRunningInstance: false
        ))
        #expect(!PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: ready,
            hasOtherRunningInstance: true
        ))
        #expect(!PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: false,
            globalStopActive: false,
            permissions: ready,
            hasOtherRunningInstance: false
        ))
    }

    @Test
    func permissionRequestFollowUpPreservesAccessibilityGuidance() {
        #expect(!PermissionRequestFollowUpPlanner.shouldAttemptListeningRestart(
            openedSettingsFallback: true,
            autoEnabled: false,
            listeningEnabled: true,
            globalStopActive: false
        ))
        #expect(PermissionRequestFollowUpPlanner.shouldAttemptListeningRestart(
            openedSettingsFallback: false,
            autoEnabled: false,
            listeningEnabled: true,
            globalStopActive: false
        ))
        #expect(!PermissionRequestFollowUpPlanner.shouldAttemptListeningRestart(
            openedSettingsFallback: false,
            autoEnabled: true,
            listeningEnabled: true,
            globalStopActive: false
        ))
        #expect(!PermissionRequestFollowUpPlanner.shouldContinueGuideAfterAccessibilityFallback(
            openedSettingsFallback: true,
            isManualRequest: true
        ))
        #expect(PermissionRequestFollowUpPlanner.shouldContinueGuideAfterAccessibilityFallback(
            openedSettingsFallback: true,
            isManualRequest: false
        ))
    }

    @Test
    func permissionDriftStopsOnlyWhenRunningPermissionsWereReady() {
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )
        #expect(PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: ready,
            current: missing,
            listeningEnabled: true,
            globalStopActive: false
        ))
        #expect(!PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: missing,
            current: missing,
            listeningEnabled: true,
            globalStopActive: false
        ))
        #expect(!PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: ready,
            current: missing,
            listeningEnabled: false,
            globalStopActive: false
        ))
        #expect(!PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: ready,
            current: missing,
            listeningEnabled: true,
            globalStopActive: true
        ))
    }

    @Test
    func tapDisabledRecoveryRequiresReadyPermissionsAndRunningState() {
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: ready
        ) == .restartListening)
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: missing
        ) == .enterPermissionBlockedStop)
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: false,
            globalStopActive: false,
            permissions: ready
        ) == .stayStopped)
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: true,
            globalStopActive: true,
            permissions: ready
        ) == .stayStopped)
    }

    @Test
    func startupAutoEnableRestoresOnlyPersistedPermissionBlockedStops() {
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        #expect(PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .permissionBlocked,
            current: ready
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .manual,
            current: ready
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .previousRunRecovery,
            current: ready
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .permissionBlocked,
            current: missing
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: true,
            stopReason: .permissionBlocked,
            current: ready
        ))
    }

    @Test
    func legacyPermissionBlockedStopReasonIsInferredOnlyForStartupGuideStops() {
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: false,
            storedStopReason: nil,
            didRunStartupPermissionGuide: true
        ) == .permissionBlocked)
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: false,
            storedStopReason: .manual,
            didRunStartupPermissionGuide: true
        ) == .manual)
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: false,
            storedStopReason: nil,
            didRunStartupPermissionGuide: false
        ) == nil)
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: true,
            storedStopReason: nil,
            didRunStartupPermissionGuide: true
        ) == nil)
    }

    @Test
    func permissionGuideRunStateIsScopedToCurrentInstallIdentity() {
        #expect(PermissionGuideRunState(
            didRunStartupGuide: true,
            storedIdentity: "old-build",
            currentIdentity: "new-build"
        ).hasRunForCurrentIdentity == false)
        #expect(PermissionGuideRunState(
            didRunStartupGuide: true,
            storedIdentity: "same-build",
            currentIdentity: "same-build"
        ).hasRunForCurrentIdentity)
        #expect(PermissionGuideRunState(
            didRunStartupGuide: false,
            storedIdentity: "same-build",
            currentIdentity: "same-build"
        ).hasRunForCurrentIdentity == false)
    }

    @Test
    func permissionGuideIdentityPersistsInSettings() {
        let suiteName = "omnivoice-permission-identity-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.startupPermissionGuideIdentity == nil)
        settings.startupPermissionGuideIdentity = "build-identity"
        #expect(settings.startupPermissionGuideIdentity == "build-identity")
    }
}
