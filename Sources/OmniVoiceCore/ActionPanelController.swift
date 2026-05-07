import AppKit

@MainActor
public final class ActionPanelController {
    private var panel: KeyableActionPanel?
    private var rootView: ActionPanelKeyView?
    private var backgroundView: ActionPanelBackgroundView?
    private var contentContainer: NSView?
    private var titleLabel: NSTextField?
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
            title: "",
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
        titleLabel?.stringValue = title
        titleLabel?.isHidden = title.isEmpty
        textView?.string = body
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

        panel.alphaValue = 1
        panel.setFrame(NSRect(frames.start), display: true)
        backgroundView?.cornerRadius = max(18, frames.start.height / 2)
        contentContainer?.alphaValue = startFrame == nil ? 1 : 0
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        rootView?.window?.makeFirstResponder(rootView)

        guard startFrame != nil else {
            panel.setFrame(NSRect(frames.final), display: true)
            backgroundView?.cornerRadius = 18
            contentContainer?.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(frames.horizontalExpanded), display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(NSRect(frames.final), display: true)
                    self.backgroundView?.animator().cornerRadius = 18
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

        let backgroundView = ActionPanelBackgroundView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.onEffectiveAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.applyPalette(status: self.currentScenario == .retry ? .warning : .normal)
        }

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 14.5, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let textView = ActionPanelTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.alignment = .center
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

        root.addSubview(backgroundView)
        backgroundView.addSubview(contentContainer)
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(scrollView)
        contentContainer.addSubview(buttonStack)
        panel.contentView = root

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: root.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

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
        let textTone: HUDTextTone
        let textShadow: NSShadow?
        if surface == .nativeGlass, let backgroundView {
            let readability = GlassReadabilityResolver.resolve(
                appearance: glassAppearance(for: backgroundView.effectiveAppearance),
                status: status
            )
            backgroundView.glassReadability = readability
            textTone = readability.textTone
            textShadow = shadow(alpha: readability.shadowAlpha)
        } else {
            let palette = HUDPaletteResolver.resolve(surface: surface, status: status)
            textTone = palette.textTone
            textShadow = nil
        }
        let textColor = textColor(for: textTone)
        titleLabel?.textColor = textColor
        textView?.textColor = textColor
        titleLabel?.shadow = textShadow
        textView?.shadow = textShadow
        for button in [primaryButton, secondaryButton, tertiaryButton] {
            button?.surface = surface
            button?.statusTone = status
            button?.glassTextTone = textTone
        }
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

private final class KeyableActionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ActionPanelKeyView: NSView {
    var onPrimary: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onPrimary?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class ActionPanelTextView: NSTextView {
    var onPrimary: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onPrimary?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class ActionPanelBackgroundView: NSView {
    @objc dynamic var cornerRadius: CGFloat = 18 {
        didSet {
            updateNativeGlassCornerRadius()
            needsDisplay = true
        }
    }

    var surface: HUDResolvedSurface = .darkCapsule {
        didSet { configureNativeGlassIfNeeded(); needsDisplay = true }
    }

    var statusTone: HUDStatusTone = .normal {
        didSet {
            updateNativeGlassAppearance()
            needsDisplay = true
        }
    }

    private var nativeGlassView: NSView?
    var onEffectiveAppearanceChanged: (() -> Void)?
    var glassReadability = GlassReadabilityResolver.resolve(appearance: .light, status: .normal) {
        didSet {
            updateNativeGlassAppearance()
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        let fillColors: [NSColor]? = switch (surface, statusTone) {
        case (.darkCapsule, .normal):
            [
                NSColor(calibratedRed: 0.050, green: 0.056, blue: 0.068, alpha: 0.99),
                NSColor(calibratedRed: 0.020, green: 0.023, blue: 0.030, alpha: 0.99)
            ]
        case (.darkCapsule, .warning):
            [
                NSColor(calibratedRed: 0.270, green: 0.135, blue: 0.072, alpha: 0.99),
                NSColor(calibratedRed: 0.135, green: 0.060, blue: 0.032, alpha: 0.99)
            ]
        case (.lightCapsule, .normal):
            [
                NSColor(calibratedRed: 0.988, green: 0.978, blue: 0.952, alpha: 0.985),
                NSColor(calibratedRed: 0.950, green: 0.940, blue: 0.915, alpha: 0.970)
            ]
        case (.lightCapsule, .warning):
            [
                NSColor(calibratedRed: 1.0, green: 0.895, blue: 0.765, alpha: 0.985),
                NSColor(calibratedRed: 0.970, green: 0.790, blue: 0.585, alpha: 0.965)
            ]
        case (.fallbackGlass, .normal):
            [
                NSColor(calibratedWhite: 1.0, alpha: 0.50),
                NSColor(calibratedWhite: 0.92, alpha: 0.36)
            ]
        case (.fallbackGlass, .warning):
            [
                NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.68, alpha: 0.58),
                NSColor(calibratedRed: 0.95, green: 0.66, blue: 0.44, alpha: 0.42)
            ]
        case (.nativeGlass, _):
            nil
        }
        if let fillColors {
            NSGradient(colors: fillColors)?.draw(in: path, angle: -90)
        } else if surface == .nativeGlass {
            color(forScrimTone: glassReadability.scrimTone, alpha: glassReadability.scrimAlpha).setFill()
            path.fill()
        }

        let innerPath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
            xRadius: max(0, radius - 1.5),
            yRadius: max(0, radius - 1.5)
        )
        NSColor.white.withAlphaComponent(statusTone == .warning ? 0.055 : 0.045).setStroke()
        innerPath.lineWidth = 0.7
        innerPath.stroke()

        let strokeColor: NSColor = switch surface {
        case .darkCapsule:
            NSColor.white.withAlphaComponent(statusTone == .warning ? 0.23 : 0.16)
        case .lightCapsule:
            NSColor.black.withAlphaComponent(statusTone == .warning ? 0.18 : 0.12)
        case .fallbackGlass, .nativeGlass:
            surface == .nativeGlass
                ? NSColor.white.withAlphaComponent(statusTone == .warning ? 0.34 : 0.28)
                : NSColor.black.withAlphaComponent(statusTone == .warning ? 0.24 : 0.14)
        }
        strokeColor.setStroke()
        path.lineWidth = 0.9
        path.stroke()
    }

    override func layout() {
        super.layout()
        updateNativeGlassCornerRadius()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChanged?()
    }

    private func updateNativeGlassAppearance() {
        guard #available(macOS 26.0, *),
              let glass = nativeGlassView as? NSGlassEffectView else {
            return
        }
        glass.tintColor = statusTone == .warning
            ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.34, alpha: glassReadability.tintAlpha)
            : NSColor(calibratedRed: 0.50, green: 0.66, blue: 0.88, alpha: glassReadability.tintAlpha)
    }

    private func updateNativeGlassCornerRadius() {
        guard #available(macOS 26.0, *),
              let glass = nativeGlassView as? NSGlassEffectView else {
            return
        }
        glass.cornerRadius = cornerRadius
    }

    private func configureNativeGlassIfNeeded() {
        nativeGlassView?.removeFromSuperview()
        nativeGlassView = nil
        guard surface == .nativeGlass,
              #available(macOS 26.0, *) else {
            return
        }
        let glass = NSGlassEffectView(frame: bounds)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.wantsLayer = true
        glass.cornerRadius = cornerRadius
        glass.style = .clear
        glass.tintColor = statusTone == .warning
            ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.34, alpha: glassReadability.tintAlpha)
            : NSColor(calibratedRed: 0.50, green: 0.66, blue: 0.88, alpha: glassReadability.tintAlpha)
        glass.clipsToBounds = true
        addSubview(glass, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        nativeGlassView = glass
    }
}

private final class ThemedPanelButton: NSButton {
    enum VisualRole {
        case primary
        case secondary
    }

    var visualRole: VisualRole = .secondary {
        didSet { needsDisplay = true }
    }

    var surface: HUDResolvedSurface = .darkCapsule {
        didSet { needsDisplay = true }
    }

    var statusTone: HUDStatusTone = .normal {
        didSet { needsDisplay = true }
    }

    var shortcutLabel: String? {
        didSet { needsDisplay = true }
    }

    var showsMenuIndicator = false {
        didSet { needsDisplay = true }
    }

    var glassTextTone: HUDTextTone = .dark {
        didSet { needsDisplay = true }
    }

    init(role: VisualRole) {
        self.visualRole = role
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 13, weight: .semibold)
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        let colors = palette()
        colors.fill.setFill()
        path.fill()
        colors.stroke.setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: colors.text,
            .paragraphStyle: paragraph
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let shortcut = shortcutLabel?.nilIfBlank
        let shortcutParagraph = NSMutableParagraphStyle()
        shortcutParagraph.alignment = .center
        shortcutParagraph.lineBreakMode = .byClipping
        let shortcutAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: colors.text.withAlphaComponent(0.72),
            .paragraphStyle: shortcutParagraph
        ]
        let shortcutSize = shortcut.map { ($0 as NSString).size(withAttributes: shortcutAttributes) } ?? .zero
        let pillPadding: CGFloat = shortcut == nil ? 0 : 10
        let pillWidth = shortcut == nil ? 0 : max(24, shortcutSize.width + pillPadding)
        let gap: CGFloat = shortcut == nil ? 0 : 7
        let indicatorWidth: CGFloat = showsMenuIndicator ? 12 : 0
        let indicatorGap: CGFloat = showsMenuIndicator ? 8 : 0
        let accessoryWidth = gap + pillWidth + indicatorGap + indicatorWidth
        let maxContentWidth = max(24, bounds.width - 24)
        let titleWidth = min(size.width, max(12, maxContentWidth - accessoryWidth))
        let totalWidth = titleWidth + accessoryWidth
        let point = NSPoint(
            x: bounds.midX - totalWidth / 2,
            y: visualTextOriginY(textHeight: size.height)
        )
        let titleRect = NSRect(x: point.x, y: point.y, width: titleWidth, height: size.height + 2)
        (title as NSString).draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
        var trailingX = titleRect.maxX
        if let shortcut {
            let pillRect = NSRect(
                x: trailingX + gap,
                y: bounds.midY - ActionPanelShortcutMetrics.bubbleHeight / 2 + ActionPanelShortcutMetrics.bubbleCenterYOffset,
                width: pillWidth,
                height: ActionPanelShortcutMetrics.bubbleHeight
            )
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 9, yRadius: 9)
            colors.text.withAlphaComponent(surface == .darkCapsule ? 0.12 : 0.10).setFill()
            pillPath.fill()
            let shortcutRect = NSRect(
                x: pillRect.minX + 2,
                y: ShortcutGlyphLayoutResolver.glyphDrawOriginY(
                    bubbleMidY: pillRect.midY,
                    glyphHeight: shortcutSize.height,
                    shortcut: shortcut
                ),
                width: max(1, pillRect.width - 4),
                height: shortcutSize.height + 2
            )
            (shortcut as NSString).draw(
                with: shortcutRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: shortcutAttributes
            )
            trailingX = pillRect.maxX
        }
        if showsMenuIndicator {
            let chevronX = trailingX + indicatorGap
            let chevronCenterY = bounds.midY + 0.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: chevronX, y: chevronCenterY + 2))
            path.line(to: NSPoint(x: chevronX + 4, y: chevronCenterY - 2))
            path.line(to: NSPoint(x: chevronX + 8, y: chevronCenterY + 2))
            colors.text.withAlphaComponent(0.72).setStroke()
            path.lineWidth = 1.35
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    private func visualTextOriginY(textHeight: CGFloat, centerY: CGFloat? = nil) -> CGFloat {
        (centerY ?? bounds.midY) - textHeight / 2 - 0.5
    }

    private func palette() -> (fill: NSColor, stroke: NSColor, text: NSColor) {
        let pressed = isHighlighted ? 0.12 : 0
        if surface == .nativeGlass {
            let text = textColor(for: glassTextTone)
            switch visualRole {
            case .primary:
                return (
                    statusTone == .warning
                        ? NSColor(calibratedRed: 0.90 - pressed, green: 0.40, blue: 0.14, alpha: 0.88)
                        : NSColor(calibratedRed: 0.12, green: 0.43 - pressed, blue: 0.90 - pressed, alpha: 0.82),
                    text.withAlphaComponent(0.14),
                    .white
                )
            case .secondary:
                return (
                    text.withAlphaComponent(isHighlighted ? 0.16 : 0.09),
                    text.withAlphaComponent(0.14),
                    text.withAlphaComponent(0.94)
                )
            }
        }
        let lightSurface = surface == .lightCapsule || surface == .fallbackGlass || surface == .nativeGlass
        switch (visualRole, lightSurface, statusTone) {
        case (.primary, false, .normal):
            return (
                NSColor(calibratedRed: 0.15, green: 0.47 - pressed, blue: 0.92 - pressed, alpha: 0.96),
                NSColor.white.withAlphaComponent(0.22),
                .white
            )
        case (.primary, false, .warning):
            return (
                NSColor(calibratedRed: 0.94 - pressed, green: 0.46 - pressed, blue: 0.20, alpha: 0.96),
                NSColor.white.withAlphaComponent(0.22),
                .white
            )
        case (.secondary, false, _):
            return (
                NSColor.white.withAlphaComponent(isHighlighted ? 0.18 : 0.11),
                NSColor.white.withAlphaComponent(0.14),
                NSColor.white.withAlphaComponent(0.92)
            )
        case (.primary, true, .normal):
            return (
                NSColor(calibratedRed: 0.12, green: 0.43 - pressed, blue: 0.90 - pressed, alpha: 0.88),
                NSColor.black.withAlphaComponent(0.12),
                .white
            )
        case (.primary, true, .warning):
            return (
                NSColor(calibratedRed: 0.86 - pressed, green: 0.36, blue: 0.10, alpha: 0.84),
                NSColor.black.withAlphaComponent(0.14),
                .white
            )
        case (.secondary, true, _):
            return (
                NSColor.black.withAlphaComponent(isHighlighted ? 0.12 : 0.07),
                NSColor.black.withAlphaComponent(0.12),
                NSColor(calibratedWhite: 0.10, alpha: 0.92)
            )
        }
    }
}

private func glassAppearance(for appearance: NSAppearance) -> GlassBackgroundAppearance {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
}

private func textColor(for tone: HUDTextTone) -> NSColor {
    switch tone {
    case .light:
        return NSColor.white.withAlphaComponent(0.96)
    case .dark:
        return NSColor(calibratedWhite: 0.08, alpha: 0.96)
    }
}

private func color(forScrimTone tone: HUDTextTone, alpha: CGFloat) -> NSColor {
    switch tone {
    case .light:
        return NSColor.white.withAlphaComponent(alpha)
    case .dark:
        return NSColor.black.withAlphaComponent(alpha)
    }
}

private func shadow(alpha: CGFloat) -> NSShadow? {
    guard alpha > 0 else { return nil }
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = 5
    shadow.shadowOffset = NSSize(width: 0, height: -0.5)
    return shadow
}

private extension NSRect {
    var cgRectValue: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
