import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

@Suite("HUD and ActionPanel")
struct HUDAndActionPanelTests {
    @Test
    func hudWidthClampsToOneThirdOfScreen() {
        #expect(HUDLayoutMetrics.clampedWidth(requestedWidth: 900, screenWidth: 1500) == 500)
        #expect(HUDLayoutMetrics.clampedWidth(requestedWidth: 120, screenWidth: 1500) == 168)
        #expect(HUDLayoutMetrics.clampedWidth(requestedWidth: 300, screenWidth: 1500) == 300)
        #expect(MenuLayoutMetrics.customViewLeading == 28)
    }
    @Test
    func hudSurfaceResolverUsesNativeGlassOnlyWhenAvailable() {
        #expect(HUDSurfaceResolver.resolve(preference: .automatic, systemAppearance: .dark, operatingSystemMajorVersion: 26, nativeGlassClassAvailable: true) == .darkCapsule)
        #expect(HUDSurfaceResolver.resolve(preference: .automatic, systemAppearance: .light, operatingSystemMajorVersion: 15, nativeGlassClassAvailable: true) == .lightCapsule)
        #expect(HUDVisualStyle.safeSelection("glass") == .lightCapsule)
        #expect(HUDSurfaceResolver.resolve(preference: .lightCapsule, operatingSystemMajorVersion: 15, nativeGlassClassAvailable: true) == .lightCapsule)
        #expect(HUDSurfaceResolver.resolve(preference: .liquidGlass, operatingSystemMajorVersion: 15, nativeGlassClassAvailable: true) == .lightCapsule)
        #expect(HUDSurfaceResolver.resolve(preference: .liquidGlass, operatingSystemMajorVersion: 26, nativeGlassClassAvailable: true) == .nativeGlass)
        #expect(HUDSurfaceResolver.resolve(preference: .darkCapsule, operatingSystemMajorVersion: 26, nativeGlassClassAvailable: true) == .darkCapsule)
        #expect(HUDVisualStyleAvailability.availableStyles(operatingSystemMajorVersion: 15, nativeGlassClassAvailable: true) == [.automatic, .darkCapsule, .lightCapsule])
        #expect(HUDVisualStyleAvailability.availableStyles(operatingSystemMajorVersion: 26, nativeGlassClassAvailable: true) == [.automatic, .darkCapsule, .lightCapsule, .liquidGlass])
        #expect(HUDVisualStyleAvailability.sanitizedSelection(.liquidGlass, operatingSystemMajorVersion: 15, nativeGlassClassAvailable: true) == .lightCapsule)
        #expect(HUDVisualStyleAvailability.sanitizedSelection(.liquidGlass, operatingSystemMajorVersion: 26, nativeGlassClassAvailable: true) == .liquidGlass)
        #expect(SurfaceHostingPolicy.contentHosting(for: .nativeGlass) == .originalContainer)
        #expect(SurfaceHostingPolicy.contentHosting(for: .darkCapsule) == .originalContainer)
        #expect(HUDPaletteResolver.resolve(surface: .lightCapsule, status: .normal).textTone == .dark)
        #expect(HUDPaletteResolver.resolve(surface: .fallbackGlass, status: .normal).textTone == .dark)
        #expect(HUDPaletteResolver.resolve(surface: .nativeGlass, status: .warning).textTone == .light)
        #expect(HUDPaletteResolver.resolve(surface: .darkCapsule, status: .normal).textTone == .light)
        #expect(HUDPaletteResolver.resolve(surface: .fallbackGlass, status: .warning).warning)
        #expect(HUDPaletteResolver.resolve(surface: .fallbackGlass, status: .normal).warning == false)

        let lightGlass = GlassReadabilityResolver.resolve(appearance: .light, status: .normal)
        let darkGlass = GlassReadabilityResolver.resolve(appearance: .dark, status: .normal)
        let warningGlass = GlassReadabilityResolver.resolve(appearance: .dark, status: .warning)
        #expect(lightGlass.textTone == .light)
        #expect(lightGlass.scrimTone == .dark)
        #expect(darkGlass.textTone == .light)
        #expect(darkGlass.scrimTone == .dark)
        #expect(darkGlass.scrimAlpha > lightGlass.scrimAlpha)
        #expect(warningGlass.tintAlpha > darkGlass.tintAlpha)
        #expect(warningGlass.scrimAlpha > darkGlass.scrimAlpha)
        #expect(!ActionPanelContentTransparencyPolicy.scrollViewDrawsBackground)
        #expect(!ActionPanelContentTransparencyPolicy.clipViewDrawsBackground)
        #expect(!ActionPanelContentTransparencyPolicy.textViewDrawsBackground)
    }
    @Test
    func waveformMotionUsesIdleAndSpeechGate() {
        let idle = WaveformMotionResolver.resolve(level: 0.01, impulse: 0.0, secondsSinceSpeech: 2.0)
        let active = WaveformMotionResolver.resolve(level: 0.22, impulse: 0.0, secondsSinceSpeech: nil)
        let releaseHeld = WaveformMotionResolver.resolve(level: 0.01, impulse: 0.0, secondsSinceSpeech: 0.12)
        let released = WaveformMotionResolver.resolve(level: 0.01, impulse: 0.0, secondsSinceSpeech: 0.35)
        #expect(!idle.active)
        #expect(active.active)
        #expect(releaseHeld.active)
        #expect(!released.active)
        #expect(active.phaseStep > idle.phaseStep * 2)
        #expect(releaseHeld.phaseStep > idle.phaseStep)
    }
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
