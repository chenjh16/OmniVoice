import AppKit

struct ActionPanelViewBundle {
    let panel: KeyableActionPanel
    let rootView: ActionPanelKeyView
    let surfaceShadowView: SurfaceShadowView
    let backgroundView: ActionPanelBackgroundView
    let contentContainer: NSView
    let titleLabel: HaloTextField
    let textView: ActionPanelTextView
    let scrollView: NSScrollView
    let buttonStack: NSStackView
    let primaryButton: ThemedPanelButton
    let secondaryButton: ThemedPanelButton
    let tertiaryButton: ThemedPanelButton
}

@MainActor
enum ActionPanelWindowFactory {
    static func make(
        owner: AnyObject,
        primarySelector: Selector,
        secondarySelector: Selector,
        tertiarySelector: Selector,
        onRootPrimary: @escaping () -> Void,
        onRootCancel: @escaping () -> Void,
        onTextPrimary: @escaping () -> Void,
        onTextCancel: @escaping () -> Void,
        onAppearanceChanged: @escaping () -> Void
    ) -> ActionPanelViewBundle {
        let panel = makePanel()
        let root = makeRootView(onPrimary: onRootPrimary, onCancel: onRootCancel)
        let surfaceShadowView = makeSurfaceShadowView()
        let backgroundView = makeBackgroundView(onAppearanceChanged: onAppearanceChanged)
        let contentContainer = makeContentContainer()
        let titleLabel = makeTitleLabel()
        let textView = makeTextView(onPrimary: onTextPrimary, onCancel: onTextCancel)
        let scrollView = makeScrollView(textView: textView)
        let buttonStack = makeButtonStack()
        let buttons = makeButtons(
            owner: owner,
            primarySelector: primarySelector,
            secondarySelector: secondarySelector,
            tertiarySelector: tertiarySelector
        )

        installHierarchy(
            panel: panel,
            root: root,
            surfaceShadowView: surfaceShadowView,
            backgroundView: backgroundView,
            contentContainer: contentContainer,
            titleLabel: titleLabel,
            scrollView: scrollView,
            buttonStack: buttonStack
        )
        installConstraints(
            root: root,
            surfaceShadowView: surfaceShadowView,
            backgroundView: backgroundView,
            contentContainer: contentContainer,
            titleLabel: titleLabel,
            scrollView: scrollView,
            buttonStack: buttonStack
        )

        return ActionPanelViewBundle(
            panel: panel,
            rootView: root,
            surfaceShadowView: surfaceShadowView,
            backgroundView: backgroundView,
            contentContainer: contentContainer,
            titleLabel: titleLabel,
            textView: textView,
            scrollView: scrollView,
            buttonStack: buttonStack,
            primaryButton: buttons.primary,
            secondaryButton: buttons.secondary,
            tertiaryButton: buttons.tertiary
        )
    }

    private static func makePanel() -> KeyableActionPanel {
        let panel = KeyableActionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 252),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        FloatingSurfacePanelConfigurator.configure(panel, role: .actionPanel)
        return panel
    }

    private static func makeRootView(onPrimary: @escaping () -> Void, onCancel: @escaping () -> Void) -> ActionPanelKeyView {
        let root = ActionPanelKeyView()
        root.onPrimary = onPrimary
        root.onCancel = onCancel
        root.wantsLayer = true
        return root
    }

    private static func makeSurfaceShadowView() -> SurfaceShadowView {
        let view = SurfaceShadowView(role: .actionPanel)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private static func makeBackgroundView(onAppearanceChanged: @escaping () -> Void) -> ActionPanelBackgroundView {
        let view = ActionPanelBackgroundView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onEffectiveAppearanceChanged = onAppearanceChanged
        return view
    }

    private static func makeContentContainer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private static func makeTitleLabel() -> HaloTextField {
        let label = HaloTextField(labelWithString: "")
        label.font = GlassTypography.actionPanelTitleFont(for: .darkCapsule)
        label.alignment = ActionPanelTextAlignmentPolicy.title
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func makeTextView(
        onPrimary: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> ActionPanelTextView {
        let textView = ActionPanelTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = ActionPanelContentTransparencyPolicy.textViewDrawsBackground
        textView.backgroundColor = .clear
        textView.alignment = ActionPanelTextAlignmentPolicy.body
        textView.font = GlassTypography.actionPanelBodyFont(for: .darkCapsule)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.onPrimary = onPrimary
        textView.onCancel = onCancel
        return textView
    }

    private static func makeScrollView(textView: ActionPanelTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = ActionPanelContentTransparencyPolicy.scrollViewDrawsBackground
        scrollView.contentView.drawsBackground = ActionPanelContentTransparencyPolicy.clipViewDrawsBackground
        scrollView.contentView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }

    private static func makeButtonStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func makeButtons(
        owner: AnyObject,
        primarySelector: Selector,
        secondarySelector: Selector,
        tertiarySelector: Selector
    ) -> (primary: ThemedPanelButton, secondary: ThemedPanelButton, tertiary: ThemedPanelButton) {
        let primaryButton = ThemedPanelButton(role: .primary)
        primaryButton.target = owner
        primaryButton.action = primarySelector
        let secondaryButton = ThemedPanelButton(role: .secondary)
        secondaryButton.target = owner
        secondaryButton.action = secondarySelector
        let tertiaryButton = ThemedPanelButton(role: .secondary)
        tertiaryButton.target = owner
        tertiaryButton.action = tertiarySelector
        for button in [primaryButton, secondaryButton, tertiaryButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 31).isActive = true
        }
        primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true
        secondaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        secondaryButton.widthAnchor.constraint(lessThanOrEqualToConstant: 230).isActive = true
        tertiaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        return (primaryButton, secondaryButton, tertiaryButton)
    }

    private static func installHierarchy(
        panel: KeyableActionPanel,
        root: ActionPanelKeyView,
        surfaceShadowView: SurfaceShadowView,
        backgroundView: ActionPanelBackgroundView,
        contentContainer: NSView,
        titleLabel: HaloTextField,
        scrollView: NSScrollView,
        buttonStack: NSStackView
    ) {
        root.addSubview(surfaceShadowView)
        root.addSubview(backgroundView)
        backgroundView.addSubview(contentContainer)
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(scrollView)
        contentContainer.addSubview(buttonStack)
        panel.contentView = root
    }

    private static func installConstraints(
        root: ActionPanelKeyView,
        surfaceShadowView: SurfaceShadowView,
        backgroundView: ActionPanelBackgroundView,
        contentContainer: NSView,
        titleLabel: HaloTextField,
        scrollView: NSScrollView,
        buttonStack: NSStackView
    ) {
        NSLayoutConstraint.activate([
            surfaceShadowView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            surfaceShadowView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            surfaceShadowView.topAnchor.constraint(equalTo: root.topAnchor),
            surfaceShadowView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            backgroundView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: SurfaceDepthMetrics.actionPanelInsets.left),
            backgroundView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -SurfaceDepthMetrics.actionPanelInsets.right),
            backgroundView.topAnchor.constraint(equalTo: root.topAnchor, constant: SurfaceDepthMetrics.actionPanelInsets.top),
            backgroundView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -SurfaceDepthMetrics.actionPanelInsets.bottom),

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
    }
}
