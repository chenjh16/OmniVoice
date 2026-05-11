import Foundation
import ApplicationServices
import AppKit
import Testing
@testable import OmniVoiceCore

@Suite("HUD and ActionPanel")
struct HUDAndActionPanelTests {
    @Test
    func hudWidthClampsToOneThirdOfScreen() {
        #expect(HUDLayoutMetrics.clampedWidth(requestedWidth: 900, screenWidth: 1500) == 500)
        #expect(HUDLayoutMetrics.clampedWidth(requestedWidth: 120, screenWidth: 1500) == 168)
        #expect(HUDLayoutMetrics.clampedWidth(requestedWidth: 300, screenWidth: 1500) == 300)
        #expect(MenuLayoutMetrics.customViewLeading == 28)
        #expect(!HUDSurfaceMetrics.usesSystemShadow)
        #expect(!ActionPanelSurfaceMetrics.usesSystemShadow)

        #expect(SurfaceDepthMetrics.hudInsets.horizontal > 0)
        #expect(SurfaceDepthMetrics.hudInsets.vertical > 0)
        #expect(SurfaceDepthMetrics.actionPanelInsets.horizontal > SurfaceDepthMetrics.hudInsets.horizontal)
        #expect(SurfaceDepthMetrics.actionPanelInsets.vertical > SurfaceDepthMetrics.hudInsets.vertical)

        let hudVisualSize = CGSize(width: 240, height: 40)
        let hudWindowSize = SurfaceDepthMetrics.windowSize(forVisualSize: hudVisualSize, role: .hud)
        #expect(hudWindowSize.width == hudVisualSize.width + SurfaceDepthMetrics.hudInsets.horizontal)
        #expect(hudWindowSize.height == hudVisualSize.height + SurfaceDepthMetrics.hudInsets.vertical)

        let visualFrame = CGRect(x: 120, y: 18, width: 240, height: 40)
        let windowFrame = SurfaceDepthMetrics.windowFrame(forVisualFrame: visualFrame, role: .hud)
        #expect(SurfaceDepthMetrics.visualFrame(forWindowFrame: windowFrame, role: .hud) == visualFrame)
        #expect(windowFrame.width > visualFrame.width)
        #expect(windowFrame.height > visualFrame.height)
    }

    @Test
    func surfaceDepthParametersUseExternalRoundedLayer() {
        for role in [SurfaceDepthRole.hud, .actionPanel] {
            for surface in [HUDResolvedSurface.darkCapsule, .lightCapsule, .fallbackGlass, .nativeGlass] {
                let normal = SurfaceDepthMetrics.parameters(role: role, surface: surface, status: .normal)
                let warning = SurfaceDepthMetrics.parameters(role: role, surface: surface, status: .warning)
                #expect(normal.hasVisibleDepth)
                #expect(warning.hasVisibleDepth)
                #expect(normal.ambientBlur > 0)
                #expect(normal.dropBlur > 0)
                #expect(normal.contactBlur > 0)
                #expect(normal.shadowSourceAlpha >= 0.30)
                #expect(normal.rimAlpha > 0)
                #expect(warning.dropAlpha >= normal.dropAlpha)
                #expect(warning.contactAlpha >= normal.contactAlpha)
            }
        }
    }

    @Test
    func liveASRPreviewPresentationUsesDraftChipWithoutPrefix() {
        let cn = HUDLivePreviewPresentationPlanner.presentation(text: "  这是实时草稿  ", badge: "草稿")
        #expect(cn == HUDLivePreviewPresentation(badge: "草稿", text: "这是实时草稿"))
        #expect(cn?.text.contains("预览：") == false)
        #expect(HUDDraftBadgeMetrics.height == 17)
        #expect(HUDDraftBadgeMetrics.horizontalPadding == 7)
        #expect(HUDDraftBadgeMetrics.width(for: "草稿") >= HUDDraftBadgeMetrics.minWidth)
        #expect(HUDLivePreviewLayoutMetrics.fadeWidth >= 100)

        let en = HUDLivePreviewPresentationPlanner.presentation(text: "  live draft  ", badge: "Draft")
        #expect(en == HUDLivePreviewPresentation(badge: "Draft", text: "live draft"))
        #expect(en?.text.contains("Preview:") == false)
        #expect(HUDLivePreviewPresentationPlanner.presentation(
            text: "  系统识别文本  ",
            badge: "识别"
        ) == HUDLivePreviewPresentation(badge: "识别", text: "系统识别文本"))
        #expect(HUDLivePreviewPresentationPlanner.presentation(
            text: "  live recognition  ",
            badge: "Live"
        ) == HUDLivePreviewPresentation(badge: "Live", text: "live recognition"))
        let multiline = HUDLivePreviewPresentationPlanner.presentation(
            text: "  嗯就会对，\n\n   然后就会出现呢像现在这样的\t大段的空格  ",
            badge: "草稿"
        )
        #expect(multiline == HUDLivePreviewPresentation(
            badge: "草稿",
            text: "嗯就会对，然后就会出现呢像现在这样的大段的空格"
        ))
        #expect(multiline?.text.contains("\n") == false)
        #expect(multiline?.text.contains("  ") == false)

        let layoutControls = HUDLivePreviewPresentationPlanner.presentation(
            text: "\u{2029}\u{2028}\u{200F}\u{202E}左边不应该空白\u{0000}\n\n\t继续识别",
            badge: "草稿"
        )
        #expect(layoutControls == HUDLivePreviewPresentation(
            badge: "草稿",
            text: "左边不应该空白继续识别"
        ))
        #expect(layoutControls?.text.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.newlines.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
                && !(0x200B...0x200F).contains(scalar.value)
                && !(0x202A...0x202E).contains(scalar.value)
                && !(0x2060...0x206F).contains(scalar.value)
        } == true)

        #expect(HUDLivePreviewPresentationPlanner.presentation(text: "   ", badge: "Draft") == nil)
        #expect(HUDLivePreviewPresentationPlanner.presentation(text: "draft", badge: "   ") == HUDLivePreviewPresentation(badge: nil, text: "draft"))
        #expect(TranscriptionHUDPresentationPolicy.showsModelProgress(for: .inputAudio))
        #expect(TranscriptionHUDPresentationPolicy.showsModelProgress(for: .systemASRTextLLM))
        #expect(!TranscriptionHUDPresentationPolicy.showsModelProgress(for: .systemASROnly))
    }

    @Test
    func transcriptionProgressCapsFollowNetworkPhase() {
        #expect(TranscriptionProgressNetworkPhaseCapPlanner.cap(for: .preparingRequest, hasReceivedDelta: false) == 0.20)
        #expect(TranscriptionProgressNetworkPhaseCapPlanner.cap(for: .connecting, hasReceivedDelta: false) == 0.36)
        #expect(TranscriptionProgressNetworkPhaseCapPlanner.cap(for: .responseReceived, hasReceivedDelta: false) == 0.56)
        #expect(TranscriptionProgressNetworkPhaseCapPlanner.cap(for: .waitingForFirstDelta, hasReceivedDelta: false) == 0.72)
        #expect(TranscriptionProgressNetworkPhaseCapPlanner.cap(for: .streaming, hasReceivedDelta: false) == 0.95)
        #expect(TranscriptionProgressNetworkPhaseCapPlanner.cap(for: .completed, hasReceivedDelta: false) == 1)
        #expect(TranscriptionProgressNetworkPhaseCapPlanner.cap(for: .connecting, hasReceivedDelta: true) == 0.95)
    }

    @Test
    func liveASRPreviewLayoutGrowsThenUsesTailFade() {
        let badgeWidth = HUDDraftBadgeMetrics.width(for: "草稿")
        let short = HUDLivePreviewLayoutPlanner.layout(
            measuredTextWidth: 110,
            measuredBadgeWidth: badgeWidth,
            includesWaveform: true,
            screenWidth: 1500
        )
        let longer = HUDLivePreviewLayoutPlanner.layout(
            measuredTextWidth: 220,
            measuredBadgeWidth: badgeWidth,
            includesWaveform: true,
            screenWidth: 1500
        )
        let capped = HUDLivePreviewLayoutPlanner.layout(
            measuredTextWidth: 900,
            measuredBadgeWidth: badgeWidth,
            includesWaveform: true,
            screenWidth: 1500
        )
        #expect(short.hudWidth < longer.hudWidth)
        #expect(longer.hudWidth < capped.hudWidth)
        #expect(capped.hudWidth == HUDLayoutMetrics.clampedWidth(requestedWidth: 10_000, screenWidth: 1500))
        #expect(short.fixedAccessoryWidth == longer.fixedAccessoryWidth)
        #expect(longer.fixedAccessoryWidth == capped.fixedAccessoryWidth)
        #expect(!short.fadeTailEnabled)
        #expect(capped.fadeTailEnabled)
        #expect(capped.textViewportWidth == capped.hudWidth - capped.fixedAccessoryWidth)

        let noBadge = HUDLivePreviewLayoutPlanner.layout(
            measuredTextWidth: 110,
            measuredBadgeWidth: 0,
            includesWaveform: true,
            screenWidth: 1500
        )
        #expect(noBadge.fixedAccessoryWidth < short.fixedAccessoryWidth)
    }

    @Test
    func liveASRPreviewSessionLayoutDoesNotShrinkUntilReset() {
        let badgeWidth = HUDDraftBadgeMetrics.width(for: "草稿")
        let long = HUDLivePreviewLayoutPlanner.layout(
            measuredTextWidth: 420,
            measuredBadgeWidth: badgeWidth,
            includesWaveform: true,
            screenWidth: 1500
        )
        let first = HUDLivePreviewSessionLayoutPlanner.layout(
            rawLayout: long,
            previous: .empty
        )
        let shorter = HUDLivePreviewLayoutPlanner.layout(
            measuredTextWidth: 80,
            measuredBadgeWidth: badgeWidth,
            includesWaveform: true,
            screenWidth: 1500
        )
        let second = HUDLivePreviewSessionLayoutPlanner.layout(
            rawLayout: shorter,
            previous: first.state
        )
        #expect(second.layout.hudWidth == first.layout.hudWidth)
        #expect(second.layout.textViewportWidth == first.layout.textViewportWidth)

        let reset = HUDLivePreviewSessionLayoutPlanner.layout(
            rawLayout: shorter,
            previous: .empty
        )
        #expect(reset.layout.hudWidth < first.layout.hudWidth)
        #expect(reset.layout.textViewportWidth < first.layout.textViewportWidth)
    }

    @Test
    func liveASRPreviewTailFitterKeepsRecentTextWithoutEllipsis() {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let mixed = "前面有很多语音识别草稿内容，最后需要保留 config.jsonc and mimo-v2.5"
        let wide = HUDLivePreviewTailFitter.visibleTail(text: mixed, availableWidth: 10_000, font: font)
        #expect(wide == mixed)

        let tail = HUDLivePreviewTailFitter.visibleTail(text: mixed, availableWidth: 150, font: font)
        #expect(!tail.contains("…"))
        #expect(mixed.hasSuffix(tail))
        #expect(tail.contains("mimo-v2.5"))
        #expect(HUDLivePreviewTailFitter.measuredWidth(tail, font: font) <= 151)
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
        let panelLightGlass = GlassReadabilityResolver.resolve(
            appearance: .light,
            status: .normal,
            role: .actionPanel
        )
        let panelDarkGlass = GlassReadabilityResolver.resolve(
            appearance: .dark,
            status: .normal,
            role: .actionPanel
        )
        let panelWarningGlass = GlassReadabilityResolver.resolve(
            appearance: .dark,
            status: .warning,
            role: .actionPanel
        )
        #expect(lightGlass.textTone == .light)
        #expect(lightGlass.scrimTone == .dark)
        #expect(lightGlass.scrimAlpha > 0.12)
        #expect(lightGlass.scrimAlpha < 0.16)
        #expect(lightGlass.tintAlpha > 0.32)
        #expect(lightGlass.tintAlpha < 0.36)
        #expect(lightGlass.materialAlpha == 1)
        #expect(lightGlass.shadowAlpha >= 0.10)
        #expect(lightGlass.haloAlpha >= 0.22)
        #expect(lightGlass.haloWidth >= 3.0)
        #expect(darkGlass.textTone == .light)
        #expect(darkGlass.scrimTone == .dark)
        #expect(darkGlass.scrimAlpha < lightGlass.scrimAlpha)
        #expect(darkGlass.scrimAlpha <= 0.08)
        #expect(darkGlass.tintAlpha < lightGlass.tintAlpha)
        #expect(darkGlass.tintAlpha <= 0.22)
        #expect(darkGlass.materialAlpha == 1)
        #expect(darkGlass.haloAlpha == lightGlass.haloAlpha)
        #expect(darkGlass.haloWidth == lightGlass.haloWidth)
        #expect(warningGlass.tintAlpha > darkGlass.tintAlpha)
        #expect(warningGlass.scrimAlpha > darkGlass.scrimAlpha)
        #expect(warningGlass.scrimAlpha <= 0.20)
        #expect(warningGlass.materialAlpha == 1)
        #expect(warningGlass.haloAlpha > darkGlass.haloAlpha)
        #expect(warningGlass.textTone == .light)
        #expect(panelLightGlass.textTone == .light)
        #expect(panelLightGlass.scrimAlpha > lightGlass.scrimAlpha)
        #expect(panelLightGlass.tintAlpha < lightGlass.tintAlpha)
        #expect(panelDarkGlass.scrimAlpha > darkGlass.scrimAlpha)
        #expect(panelDarkGlass.tintAlpha < darkGlass.tintAlpha)
        #expect(panelLightGlass.haloAlpha > lightGlass.haloAlpha)
        #expect(panelWarningGlass.scrimAlpha < warningGlass.scrimAlpha)
        #expect(panelWarningGlass.tintAlpha < warningGlass.tintAlpha)
        let text = NSAttributedString(
            string: "Liquid Glass",
            attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white]
        )
        let halo = GlassTextReadabilityRenderer.haloAttributedString(
            from: text,
            haloColor: textHaloColor(for: lightGlass.textTone, alpha: lightGlass.haloAlpha),
            haloWidth: lightGlass.haloWidth
        )
        let strokeWidth = halo?.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? CGFloat
        #expect(strokeWidth == lightGlass.haloWidth)
        #expect((strokeWidth ?? 0) > 0)
        #expect(NativeGlassSurfaceStyle.topSheenAlpha == 0)
        #expect(NativeGlassSurfaceStyle.bottomShadeAlpha == 0)
        #expect(NativeGlassSurfaceStyle.innerRimAlpha(status: .normal) == 0.18)
        #expect(NativeGlassSurfaceStyle.innerRimAlpha(status: .warning) == 0.24)
        #expect(NativeGlassSurfaceStyle.topSheenAlpha(role: .hud, status: .normal) == 0)
        #expect(NativeGlassSurfaceStyle.bottomShadeAlpha(role: .hud, status: .normal) == 0)
        #expect(NativeGlassSurfaceStyle.topSheenAlpha(role: .actionPanel, status: .normal) == 0)
        #expect(NativeGlassSurfaceStyle.bottomShadeAlpha(role: .actionPanel, status: .normal) == 0)
        if #available(macOS 26.0, *) {
            #expect(NativeGlassSurfaceStyle.glassStyle(role: .actionPanel, status: .normal) == .regular)
            #expect(NativeGlassSurfaceStyle.glassStyle(role: .actionPanel, status: .warning) == .regular)
            #expect(NativeGlassSurfaceStyle.glassStyle(role: .hud, status: .normal) == .regular)
        }
        #expect(
            NativeGlassSurfaceStyle.innerRimAlpha(status: .normal, role: .actionPanel)
                > NativeGlassSurfaceStyle.innerRimAlpha(status: .normal, role: .hud)
        )
        #expect(NativeGlassSurfaceStyle.overlayColor(status: .normal, readability: lightGlass).alphaComponent == lightGlass.scrimAlpha)
        #expect(NativeGlassSurfaceStyle.overlayColor(status: .warning, readability: warningGlass).alphaComponent == warningGlass.scrimAlpha)
        #expect(
            GlassTypography.compactWeight(for: .nativeGlass).rawValue
                > GlassTypography.compactWeight(for: .darkCapsule).rawValue
        )
        #expect(
            GlassTypography.panelWeight(for: .nativeGlass).rawValue
                > GlassTypography.panelWeight(for: .lightCapsule).rawValue
        )
        #expect(GlassTypography.hudTextFont(for: .nativeGlass).fontDescriptor.pointSize == 12.5)
        #expect(GlassTypography.actionPanelTitleFont(for: .nativeGlass).fontDescriptor.pointSize == 14.5)
        #expect(GlassTypography.panelButtonHaloAlphaScale >= 0.90)
        #expect(GlassTypography.panelButtonHaloWidthScale == 1.0)
        #expect(!ActionPanelContentTransparencyPolicy.scrollViewDrawsBackground)
        #expect(!ActionPanelContentTransparencyPolicy.clipViewDrawsBackground)
        #expect(!ActionPanelContentTransparencyPolicy.textViewDrawsBackground)
        #expect(ActionPanelTextAlignmentPolicy.title == .center)
        #expect(ActionPanelTextAlignmentPolicy.body == .natural)
    }
}
