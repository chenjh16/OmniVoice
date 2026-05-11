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
        root.onPrimary = onRootPrimary
        root.onCancel = onRootCancel
        root.wantsLayer = true

        let surfaceShadowView = SurfaceShadowView(role: .actionPanel)
        surfaceShadowView.translatesAutoresizingMaskIntoConstraints = false

        let backgroundView = ActionPanelBackgroundView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.onEffectiveAppearanceChanged = onAppearanceChanged

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
        textView.onPrimary = onTextPrimary
        textView.onCancel = onTextCancel

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
            primaryButton: primaryButton,
            secondaryButton: secondaryButton,
            tertiaryButton: tertiaryButton
        )
    }
}
