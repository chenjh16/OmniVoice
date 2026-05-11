import Foundation
import Testing
@testable import OmniVoiceCore

extension ConfigurationTests {

    @Test
    func configValidationLoadAndSnapshotExportSupportHotReloadFallback() throws {
        let fixture = try configFixture(slug: "omnivoice-hot-reload")
        let loader = fixture.loader

        try Data("{ nope".utf8).write(to: fixture.configURL)
        #expect(loader.loadValidConfigWithoutRepair() == .invalid(["unreadable"]))

        let valid = ConfigTemplateBuilder.template(uiLanguage: .english)
        try fixture.write(valid)
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
    func configHotReloadControllerHandlesIgnorePendingAndInvalidFingerprints() throws {
        var controller = ConfigHotReloadController()
        let start = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 5,
            day: 9,
            hour: 10
        )))

        controller.markInternalWrite(now: start, ignoreDuration: 2)
        #expect(controller.handleFileChanged(now: start.addingTimeInterval(1), isIdle: true) == .ignore)
        #expect(controller.handleFileChanged(now: start.addingTimeInterval(3), isIdle: false) == .markPending)
        let consumedWhileBusy = controller.consumePendingIfIdle(isIdle: false)
        let consumedWhenIdle = controller.consumePendingIfIdle(isIdle: true)
        let consumedAgain = controller.consumePendingIfIdle(isIdle: true)
        #expect(!consumedWhileBusy)
        #expect(consumedWhenIdle)
        #expect(!consumedAgain)

        let firstFingerprint = ConfigHotReloadController.fingerprint(data: Data("bad config".utf8))
        let shouldReportFirstInvalid = controller.shouldReportInvalidConfig(fingerprint: firstFingerprint)
        let shouldReportFirstInvalidAgain = controller.shouldReportInvalidConfig(fingerprint: firstFingerprint)
        #expect(shouldReportFirstInvalid)
        #expect(!shouldReportFirstInvalidAgain)
        controller.setInvalidMessage("Fix config.jsonc")
        #expect(controller.lastMessage == "Fix config.jsonc")
        #expect(controller.lastInvalidFingerprint == firstFingerprint)

        let secondFingerprint = ConfigHotReloadController.fingerprint(data: Data("different bad config".utf8))
        let shouldReportSecondInvalid = controller.shouldReportInvalidConfig(fingerprint: secondFingerprint)
        #expect(shouldReportSecondInvalid)
        controller.markValidApplied()
        #expect(controller.lastMessage == nil)
        #expect(controller.lastInvalidFingerprint == nil)
        #expect(ConfigHotReloadController.fingerprint(data: nil) == "missing")
    }
}
