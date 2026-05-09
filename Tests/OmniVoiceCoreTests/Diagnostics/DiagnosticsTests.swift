import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test
    func diagnosticsRedactSecrets() {
        let secret = "sk-abcdefghijklmnopqrstuvwxyz1234567890TOKEN"
        let diagnostic = RuntimeDiagnostic(
            stage: "transcribe_http",
            host: "token-plan-sgp.xiaomimimo.com",
            model: "mimo-v2-omni",
            recordingSeconds: 1.2,
            wavBytes: 32044,
            rms: 0.05,
            httpStatus: 401,
            contentType: "application/json",
            errorKind: "authentication_failed",
            errorPreview: #"{"api_key":"\#(secret)","message":"bad key"}"#
        )
        #expect(!diagnostic.clipboardText.contains(secret))
        #expect(diagnostic.clipboardText.contains("<redacted>"))
        #expect(diagnostic.menuSummary == "transcribe_http: authentication_failed")
    }
    @Test
    func diagnosticsRedactInjectionDetails() {
        let secret = "token_abcdefghijklmnopqrstuvwxyz1234567890"
        let diagnostic = RuntimeDiagnostic(
            stage: "pasteboard_write",
            host: "local",
            errorKind: "pasteboard_write_failed",
            details: [
                "text_chars": "12",
                "target_app": "TextEdit",
                "api_key": secret
            ]
        )
        #expect(diagnostic.clipboardText.contains("text_chars: 12"))
        #expect(diagnostic.clipboardText.contains("target_app: TextEdit"))
        #expect(!diagnostic.clipboardText.contains(secret))
        #expect(diagnostic.clipboardText.contains("api_key: <redacted>"))
    }
}
