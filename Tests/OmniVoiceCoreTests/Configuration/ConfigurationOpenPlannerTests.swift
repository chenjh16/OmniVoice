import Foundation
import Testing
@testable import OmniVoiceCore

extension ConfigurationTests {

    @Test
    func configFileLineLocatorFindsKnownSections() throws {
        let document = ConfigDocumentWriter.defaultDocument(uiLanguage: .english)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .root) == 1)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .sources) > 1)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .modelsAudioLLM) > 1)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .modelsTextLLM) > 1)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .keywordGroups) > 1)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .customStyles) > 1)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .systemASR) > 1)
        #expect(ConfigFileLineLocator.lineNumber(in: document, section: .preferences) > 1)
        #expect(ConfigFileLineLocator.lineNumber(in: #"{"models": {}}"#, section: .keywordGroups) == 1)
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
        let configURL = root.appendingPathComponent("config.jsonc")

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
            executableDirectories: [bin],
            fileURL: configURL,
            line: 42,
            column: 3
        )
        #expect(commandPlan.method == .command(codeCommand, displayName: "Visual Studio Code"))
        #expect(commandPlan.arguments == ["--goto", "\(configURL.path):42:3"])

        try FileManager.default.removeItem(at: codeCommand)
        let zedCommand = bin.appendingPathComponent("zed")
        try Data("#!/bin/sh\n".utf8).write(to: zedCommand)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: zedCommand.path)
        let zedPlan = ConfigFileOpenPlanner.plan(
            applicationsDirectories: [apps, homeApps],
            executableDirectories: [bin],
            fileURL: configURL,
            line: 8,
            column: 1
        )
        #expect(zedPlan.method == .command(zedCommand, displayName: "Zed"))
        #expect(zedPlan.arguments == ["\(configURL.path):8:1"])

        try FileManager.default.removeItem(at: zedCommand)
        let xedCommand = bin.appendingPathComponent("xed")
        try Data("#!/bin/sh\n".utf8).write(to: xedCommand)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xedCommand.path)
        let xedPlan = ConfigFileOpenPlanner.plan(
            applicationsDirectories: [apps, homeApps],
            executableDirectories: [bin],
            fileURL: configURL,
            line: 9,
            column: 1
        )
        #expect(xedPlan.method == .command(xedCommand, displayName: "Xcode"))
        #expect(xedPlan.arguments == ["-l", "9", configURL.path])

        let fallbackPlan = ConfigFileOpenPlanner.plan(
            applicationsDirectories: [root.appendingPathComponent("missing-apps", isDirectory: true)],
            executableDirectories: [root.appendingPathComponent("missing-bin", isDirectory: true)]
        )
        #expect(fallbackPlan.method == .systemDefault)
    }
}
