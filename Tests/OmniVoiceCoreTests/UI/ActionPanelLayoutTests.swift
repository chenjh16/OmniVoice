import Foundation
import AppKit
import Testing
@testable import OmniVoiceCore

@Suite("ActionPanel layout")
struct ActionPanelLayoutTests {
    @Test
    func morphingPanelFramesExpandFromHUDFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let hudFrame = CGRect(x: 600, y: 18, width: 240, height: 40)
        let frames = MorphingPanelFramePlanner.frames(start: hudFrame, screen: screen)
        #expect(frames.start == hudFrame)
        #expect(frames.horizontalExpanded.height == hudFrame.height)
        #expect(frames.horizontalExpanded.width > hudFrame.width)
        #expect(frames.horizontalExpanded.midX == hudFrame.midX)
        #expect(frames.final.width == frames.horizontalExpanded.width)
        #expect(frames.final.height > frames.horizontalExpanded.height)
        #expect(frames.final.minY == hudFrame.minY)
        #expect(frames.final.minX >= 24)
        #expect(frames.final.maxX <= screen.maxX - 24)
        #expect(frames.final.maxY <= screen.maxY - 24)

        let startWindow = SurfaceDepthMetrics.windowFrame(forVisualFrame: frames.start, role: .actionPanel)
        let finalWindow = SurfaceDepthMetrics.windowFrame(forVisualFrame: frames.final, role: .actionPanel)
        #expect(startWindow.width == frames.start.width + SurfaceDepthMetrics.actionPanelInsets.horizontal)
        #expect(startWindow.height == frames.start.height + SurfaceDepthMetrics.actionPanelInsets.vertical)
        #expect(finalWindow.width == frames.final.width + SurfaceDepthMetrics.actionPanelInsets.horizontal)
        #expect(finalWindow.height == frames.final.height + SurfaceDepthMetrics.actionPanelInsets.vertical)
        #expect(SurfaceDepthMetrics.visualFrame(forWindowFrame: finalWindow, role: .actionPanel) == frames.final)

        let shortSize = ActionPanelSizePlanner.size(
            bodyCharacterCount: 12,
            lineBreakCount: 0,
            hasTitle: false,
            screen: screen.size,
            scenario: .result
        )
        let longSize = ActionPanelSizePlanner.size(
            bodyCharacterCount: 420,
            lineBreakCount: 4,
            hasTitle: true,
            screen: screen.size,
            scenario: .result
        )
        #expect(longSize.height > shortSize.height)
        #expect(longSize.height <= screen.height * 0.48)
    }

    @Test
    func actionPanelButtonsMatchRetryAndResultScenarios() {
        let retry = ActionPanelButtonLayoutPlanner.layout(for: .retry)
        #expect(retry.order == [.retry, .cancel])
        #expect(retry.primary == .retry)
        #expect(retry.escape == .cancel)
        #expect(retry.shortcuts[.retry] == "↩")
        #expect(retry.shortcuts[.cancel] == "Esc")

        let result = ActionPanelButtonLayoutPlanner.layout(for: .result)
        #expect(result.order == [.copy, .styleSwitcher, .cancel])
        #expect(result.primary == .copy)
        #expect(result.escape == .cancel)
        #expect(result.shortcuts[.copy] == "↩")
        #expect(result.shortcuts[.cancel] == "Esc")
        let option = ActionPanelStyleOption(selection: .builtIn(.rewrite), title: "Rewrite", tooltip: "Rewrite speech")
        #expect(option.selection.builtInStyle == .rewrite)
        #expect(!ActionPanelSurfaceMetrics.usesSystemShadow)
        #expect(ActionPanelShortcutMetrics.glyphBaselineOffset(for: "↩", glyphHeight: 10) == 1.5)
        #expect(ActionPanelShortcutMetrics.glyphBaselineOffset(for: "Esc", glyphHeight: 10) == 0.0)
        #expect(ActionPanelShortcutMetrics.glyphBaselineOffset(for: "↩") > ActionPanelShortcutMetrics.glyphBaselineOffset(for: "Esc"))
        #expect(ShortcutGlyphLayoutResolver.glyphDrawOriginY(bubbleMidY: 10, glyphHeight: 10, shortcut: "↩") > ShortcutGlyphLayoutResolver.glyphDrawOriginY(bubbleMidY: 10, glyphHeight: 10, shortcut: "Esc"))
        #expect(ActionPanelShortcutMetrics.bubbleCenterYOffset == 0)
        #expect(RestartAppPlanner.bundleURL(currentBundleURL: URL(fileURLWithPath: "/tmp/OmniVoice.app")).path == "/tmp/OmniVoice.app")
        #expect(RestartAppPlanner.bundleURL(currentBundleURL: URL(fileURLWithPath: "/tmp/OmniVoice")).path == "/Applications/OmniVoice.app")
    }
}
