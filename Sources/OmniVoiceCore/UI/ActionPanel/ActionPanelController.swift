import AppKit

@MainActor
public final class ActionPanelController {
    private var panel: KeyableActionPanel?
    private var rootView: ActionPanelKeyView?
    private var surfaceShadowView: SurfaceShadowView?
    private var backgroundView: ActionPanelBackgroundView?
    private var contentContainer: NSView?
    private var titleLabel: HaloTextField?
    private var textView: ActionPanelTextView?
    private var scrollView: NSScrollView?
    private var buttonStack: NSStackView?
    private var primaryButton: ThemedPanelButton?
    private var secondaryButton: ThemedPanelButton?
    private var tertiaryButton: ThemedPanelButton?
    private var copiedTitle = "已复制"
    private var currentText = ""
    private var visualStyle: HUDVisualStyle = .automatic
    private var currentScenario: ActionPanelScenario = .result
    private var styleOptions: [ActionPanelStyleOption] = []
    private var selectedStyle: TranscriptionStyleSelection?
    private var panelTextColor = NSColor.white.withAlphaComponent(0.96)
    private var panelTextShadow: NSShadow?
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?
    private var tertiaryAction: (() -> Void)?
    private var cancelAction: (() -> Void)?
    private var styleSelectionAction: ((TranscriptionStyleSelection) -> Void)?

    public init() {}

    public var diagnosticSnapshot: SurfaceDiagnosticSnapshot {
        SurfaceDiagnosticSnapshot(
            panelType: "keyable_action_panel",
            levelName: "statusBar",
            isVisible: panel?.isVisible ?? false,
            frame: panel?.isVisible == true ? panel?.frame.cgRectValue : nil,
            windowNumber: panel?.isVisible == true ? panel?.windowNumber : nil
        )
    }

    public func renderedPNGData() -> Data? {
        guard panel?.isVisible == true, let contentView = panel?.contentView else { return nil }
        return contentView.omniVoiceRenderedPNGData()
    }

    public func setVisualStyle(_ style: HUDVisualStyle) {
        visualStyle = style
        applyPalette(status: currentScenario == .retry ? .warning : .normal)
    }

    public func showResult(
        title: String = "",
        text: String,
        copyTitle: String,
        styleTitle: String,
        styleOptions: [ActionPanelStyleOption],
        selectedStyle: TranscriptionStyleSelection,
        cancelTitle: String,
        copiedTitle: String,
        from startFrame: NSRect? = nil,
        onCopy: (() -> Void)? = nil,
        onStyleSelected: ((TranscriptionStyleSelection) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        currentScenario = .result
        currentText = text
        self.copiedTitle = copiedTitle
        self.styleOptions = styleOptions
        self.selectedStyle = selectedStyle
        styleSelectionAction = onStyleSelected
        primaryAction = { [weak self] in
            self?.copyAndClose()
            onCopy?()
        }
        secondaryAction = { [weak self] in
            self?.showStyleMenu()
        }
        tertiaryAction = { [weak self] in
            self?.cancel()
            onCancel?()
        }
        cancelAction = tertiaryAction
        showPanel(
            scenario: .result,
            title: title,
            body: text,
            copyTitle: copyTitle,
            retryTitle: styleTitle,
            cancelTitle: cancelTitle,
            from: startFrame
        )
    }

    public func showRetry(
        title: String,
        message: String,
        retryTitle: String,
        cancelTitle: String,
        from startFrame: NSRect? = nil,
        onRetry: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        currentScenario = .retry
        currentText = ""
        styleOptions = []
        selectedStyle = nil
        styleSelectionAction = nil
        primaryAction = { [weak self] in
            self?.cancel()
            onRetry?()
        }
        secondaryAction = nil
        tertiaryAction = { [weak self] in
            self?.cancel()
            onCancel?()
        }
        cancelAction = tertiaryAction
        showPanel(
            scenario: .retry,
            title: title,
            body: message,
            copyTitle: nil,
            retryTitle: retryTitle,
            cancelTitle: cancelTitle,
            from: startFrame
        )
    }

    public func cancel() {
        panel?.orderOut(nil)
        currentText = ""
        primaryAction = nil
        secondaryAction = nil
        tertiaryAction = nil
        cancelAction = nil
        styleSelectionAction = nil
        styleOptions = []
        selectedStyle = nil
    }

    private func showPanel(
        scenario: ActionPanelScenario,
        title: String,
        body: String,
        copyTitle: String?,
        retryTitle: String,
        cancelTitle: String,
        from startFrame: NSRect?
    ) {
        let panel = ensurePanel()
        currentScenario = scenario
        applyPalette(status: scenario == .retry ? .warning : .normal)
        titleLabel?.isHidden = title.isEmpty
        setTitleText(title)
        setBodyText(body)
        textView?.scrollToBeginningOfDocument(nil)
        configureButtons(
            scenario: scenario,
            copyTitle: copyTitle,
            retryTitle: retryTitle,
            cancelTitle: cancelTitle
        )

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let finalSize = ActionPanelSizePlanner.size(
            bodyCharacterCount: body.count,
            lineBreakCount: body.filter { $0 == "\n" }.count,
            hasTitle: !title.isEmpty,
            screen: screenFrame.size,
            scenario: scenario
        )
        let frames = MorphingPanelFramePlanner.frames(
            start: startFrame?.cgRectValue,
            screen: screenFrame.cgRectValue,
            finalSize: finalSize
        )
        let windowFrames = MorphingPanelFrames(
            start: SurfaceDepthMetrics.windowFrame(forVisualFrame: frames.start, role: .actionPanel),
            horizontalExpanded: SurfaceDepthMetrics.windowFrame(
                forVisualFrame: frames.horizontalExpanded,
                role: .actionPanel
            ),
            final: SurfaceDepthMetrics.windowFrame(forVisualFrame: frames.final, role: .actionPanel)
        )
        let startCornerRadius = max(18, frames.start.height / 2)

        panel.alphaValue = 1
        panel.setFrame(NSRect(windowFrames.start), display: true)
        backgroundView?.cornerRadius = startCornerRadius
        surfaceShadowView?.cornerRadius = startCornerRadius
        contentContainer?.alphaValue = startFrame == nil ? 1 : 0
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        rootView?.window?.makeFirstResponder(rootView)

        guard startFrame != nil else {
            panel.setFrame(NSRect(windowFrames.final), display: true)
            backgroundView?.cornerRadius = 18
            surfaceShadowView?.cornerRadius = 18
            contentContainer?.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(windowFrames.horizontalExpanded), display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(NSRect(windowFrames.final), display: true)
                    self.backgroundView?.animator().cornerRadius = 18
                    self.surfaceShadowView?.animator().cornerRadius = 18
                    self.contentContainer?.animator().alphaValue = 1
                }
            }
        }
    }

    private func ensurePanel() -> KeyableActionPanel {
        if let panel { return panel }

        let panel = KeyableActionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 252),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = ActionPanelSurfaceMetrics.usesSystemShadow
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let root = ActionPanelKeyView()
        root.onPrimary = { [weak self] in self?.primaryAction?() }
        root.onCancel = { [weak self] in self?.cancelAction?() }
        root.wantsLayer = true

        let surfaceShadowView = SurfaceShadowView(role: .actionPanel)
        surfaceShadowView.translatesAutoresizingMaskIntoConstraints = false

        let backgroundView = ActionPanelBackgroundView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.onEffectiveAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.applyPalette(status: self.currentScenario == .retry ? .warning : .normal)
        }

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = HaloTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 14.5, weight: .semibold)
        titleLabel.alignment = ActionPanelTextAlignmentPolicy.title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textView = ActionPanelTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.alignment = ActionPanelTextAlignmentPolicy.body
        textView.font = .systemFont(ofSize: 14, weight: .semibold)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.onPrimary = { [weak self] in self?.primaryAction?() }
        textView.onCancel = { [weak self] in self?.cancelAction?() }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = ActionPanelContentTransparencyPolicy.scrollViewDrawsBackground
        scrollView.contentView.drawsBackground = ActionPanelContentTransparencyPolicy.clipViewDrawsBackground
        scrollView.contentView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        textView.drawsBackground = ActionPanelContentTransparencyPolicy.textViewDrawsBackground
        textView.backgroundColor = .clear

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        buttonStack.spacing = 10
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let primaryButton = ThemedPanelButton(role: .primary)
        primaryButton.target = self
        primaryButton.action = #selector(primaryButtonPressed)
        let secondaryButton = ThemedPanelButton(role: .secondary)
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryButtonPressed)
        let tertiaryButton = ThemedPanelButton(role: .secondary)
        tertiaryButton.target = self
        tertiaryButton.action = #selector(tertiaryButtonPressed)
        for button in [primaryButton, secondaryButton, tertiaryButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 31).isActive = true
        }
        primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true
        secondaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        secondaryButton.widthAnchor.constraint(lessThanOrEqualToConstant: 230).isActive = true
        tertiaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true

        root.addSubview(surfaceShadowView)
        root.addSubview(backgroundView)
        backgroundView.addSubview(contentContainer)
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(scrollView)
        contentContainer.addSubview(buttonStack)
        panel.contentView = root

        NSLayoutConstraint.activate([
            surfaceShadowView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            surfaceShadowView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            surfaceShadowView.topAnchor.constraint(equalTo: root.topAnchor),
            surfaceShadowView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            backgroundView.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: SurfaceDepthMetrics.actionPanelInsets.left
            ),
            backgroundView.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -SurfaceDepthMetrics.actionPanelInsets.right
            ),
            backgroundView.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: SurfaceDepthMetrics.actionPanelInsets.top
            ),
            backgroundView.bottomAnchor.constraint(
                equalTo: root.bottomAnchor,
                constant: -SurfaceDepthMetrics.actionPanelInsets.bottom
            ),

            contentContainer.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 26),
            titleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -26),
            titleLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 18),

            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 28),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -28),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -16),

            buttonStack.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -18),
            buttonStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 31)
        ])

        self.panel = panel
        self.rootView = root
        self.surfaceShadowView = surfaceShadowView
        self.backgroundView = backgroundView
        self.contentContainer = contentContainer
        self.titleLabel = titleLabel
        self.textView = textView
        self.scrollView = scrollView
        self.buttonStack = buttonStack
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
        self.tertiaryButton = tertiaryButton
        return panel
    }

    private func configureButtons(
        scenario: ActionPanelScenario,
        copyTitle: String?,
        retryTitle: String,
        cancelTitle: String
    ) {
        guard let buttonStack, let primaryButton, let secondaryButton, let tertiaryButton else { return }
        buttonStack.arrangedSubviews.forEach { view in
            buttonStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let layout = ActionPanelButtonLayoutPlanner.layout(for: scenario)
        primaryButton.title = scenario == .retry ? retryTitle : (copyTitle ?? "")
        primaryButton.keyEquivalent = layout.primary == .copy || layout.primary == .retry ? "\r" : ""
        primaryButton.visualRole = .primary
        primaryButton.shortcutLabel = layout.shortcuts[layout.primary]
        secondaryButton.title = retryTitle
        secondaryButton.keyEquivalent = ""
        secondaryButton.visualRole = .secondary
        secondaryButton.shortcutLabel = layout.shortcuts[.styleSwitcher]
        secondaryButton.showsMenuIndicator = scenario == .result
        tertiaryButton.title = cancelTitle
        tertiaryButton.keyEquivalent = layout.primary == .cancel ? "\r" : ""
        tertiaryButton.visualRole = .secondary
        tertiaryButton.shortcutLabel = layout.shortcuts[.cancel]
        tertiaryButton.showsMenuIndicator = false
        primaryButton.showsMenuIndicator = false

        let buttonsByRole: [ActionPanelButtonRole: NSButton] = [
            .copy: primaryButton,
            .retry: primaryButton,
            .styleSwitcher: secondaryButton,
            .cancel: tertiaryButton
        ]
        for role in layout.order {
            guard let button = buttonsByRole[role] else { continue }
            buttonStack.addArrangedSubview(button)
        }
    }

    private func applyPalette(status: HUDStatusTone) {
        let surface = HUDSurfaceResolver.resolve(
            preference: visualStyle,
            systemAppearance: backgroundView.map { glassAppearance(for: $0.effectiveAppearance) } ?? .dark
        )
        backgroundView?.surface = surface
        backgroundView?.statusTone = status
        surfaceShadowView?.surface = surface
        surfaceShadowView?.status = status
        let textTone: HUDTextTone
        let textShadow: NSShadow?
        if surface == .nativeGlass, let backgroundView {
            let readability = GlassReadabilityResolver.resolve(
                appearance: glassAppearance(for: backgroundView.effectiveAppearance),
                status: status
            )
            backgroundView.glassReadability = readability
            textTone = readability.textTone
            textShadow = actionPanelTextShadow(alpha: readability.shadowAlpha)
        } else {
            let palette = HUDPaletteResolver.resolve(surface: surface, status: status)
            textTone = palette.textTone
            textShadow = nil
        }
        let textColor = textColor(for: textTone)
        panelTextColor = textColor
        panelTextShadow = textShadow
        titleLabel?.textColor = textColor
        textView?.textColor = textColor
        titleLabel?.shadow = textShadow
        textView?.shadow = textShadow
        if surface == .nativeGlass {
            let readability = backgroundView.map {
                GlassReadabilityResolver.resolve(
                    appearance: glassAppearance(for: $0.effectiveAppearance),
                    status: status
                )
            }
            titleLabel?.textHaloColor = textHaloColor(for: textTone, alpha: readability?.haloAlpha ?? 0)
            titleLabel?.textHaloWidth = readability?.haloWidth ?? 0
        } else {
            titleLabel?.textHaloColor = nil
            titleLabel?.textHaloWidth = 0
        }
        if let titleLabel {
            setTitleText(titleLabel.stringValue)
        }
        if let textView {
            setBodyText(textView.string)
        }
        for button in [primaryButton, secondaryButton, tertiaryButton] {
            button?.surface = surface
            button?.statusTone = status
            button?.glassTextTone = textTone
            if surface == .nativeGlass, let backgroundView {
                let readability = GlassReadabilityResolver.resolve(
                    appearance: glassAppearance(for: backgroundView.effectiveAppearance),
                    status: status
                )
                button?.glassTextHaloColor = textHaloColor(for: textTone, alpha: readability.haloAlpha * 0.72)
                button?.glassTextHaloWidth = readability.haloWidth * 0.84
            } else {
                button?.glassTextHaloColor = nil
                button?.glassTextHaloWidth = 0
            }
        }
    }

    private func setTitleText(_ title: String) {
        guard let titleLabel else { return }
        titleLabel.stringValue = title
        titleLabel.needsDisplay = true
    }

    private func setBodyText(_ body: String) {
        guard let textView else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ActionPanelTextAlignmentPolicy.body
        paragraph.lineBreakMode = .byWordWrapping
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: body,
            attributes: textAttributes(
                font: textView.font ?? .systemFont(ofSize: 14, weight: .semibold),
                paragraph: paragraph
            )
        ))
    }

    private func textAttributes(font: NSFont, paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: panelTextColor,
            .paragraphStyle: paragraph
        ]
        if let panelTextShadow {
            attributes[.shadow] = panelTextShadow
        }
        return attributes
    }

    @objc private func primaryButtonPressed() {
        primaryAction?()
    }

    @objc private func secondaryButtonPressed() {
        secondaryAction?()
    }

    @objc private func tertiaryButtonPressed() {
        tertiaryAction?()
    }

    private func showStyleMenu() {
        guard currentScenario == .result,
              !styleOptions.isEmpty,
              let secondaryButton else { return }
        let menu = NSMenu()
        for option in styleOptions {
            let item = NSMenuItem(title: option.title, action: #selector(styleMenuItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.selection.rawValue
            item.toolTip = option.tooltip
            item.state = option.selection == selectedStyle ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: secondaryButton.bounds.height + 6),
            in: secondaryButton
        )
    }

    @objc private func styleMenuItemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let selection = TranscriptionStyleSelection(rawValue: raw)
        guard selection != selectedStyle else { return }
        selectedStyle = selection
        let action = styleSelectionAction
        cancel()
        action?(selection)
    }

    private func copyAndClose() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentText, forType: .string)
        primaryButton?.title = copiedTitle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.cancel()
        }
    }
}

private func actionPanelTextShadow(alpha: CGFloat) -> NSShadow? {
    guard alpha > 0 else { return nil }
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = 4
    shadow.shadowOffset = NSSize(width: 0, height: -0.5)
    return shadow
}
