import AppKit

struct NativeGlassBackplateDescriptor {
    let surface: HUDResolvedSurface
    let role: GlassSurfaceRole
    let status: HUDStatusTone
    let readability: GlassReadabilityStyle
    let cornerRadius: CGFloat
}

final class NativeGlassBackplate {
    private weak var owner: NSView?
    private var glassView: NSView?
    private var scrimView: GlassScrimView?

    init(owner: NSView) {
        self.owner = owner
    }

    func configureIfNeeded(
        surface: HUDResolvedSurface,
        role: GlassSurfaceRole,
        status: HUDStatusTone,
        readability: GlassReadabilityStyle,
        cornerRadius: CGFloat
    ) {
        remove()
        guard surface == .nativeGlass,
              #available(macOS 26.0, *),
              let owner else {
            return
        }

        let glass = NSGlassEffectView(frame: owner.bounds)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.cornerRadius = cornerRadius
        glass.style = NativeGlassSurfaceStyle.glassStyle(role: role, status: status)
        glass.tintColor = NativeGlassSurfaceStyle.tintColor(status: status, readability: readability)
        glass.alphaValue = 1
        owner.addSubview(glass, positioned: .below, relativeTo: nil)
        pinToOwner(glass, owner: owner)

        let scrim = GlassScrimView()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.cornerRadius = cornerRadius
        applyOverlay(to: scrim, role: role, status: status, readability: readability)
        owner.addSubview(scrim, positioned: .above, relativeTo: glass)
        pinToOwner(scrim, owner: owner)

        glassView = glass
        scrimView = scrim
    }

    func configureIfNeeded(_ descriptor: NativeGlassBackplateDescriptor) {
        configureIfNeeded(
            surface: descriptor.surface,
            role: descriptor.role,
            status: descriptor.status,
            readability: descriptor.readability,
            cornerRadius: descriptor.cornerRadius
        )
    }

    func updateAppearance(
        role: GlassSurfaceRole,
        status: HUDStatusTone,
        readability: GlassReadabilityStyle
    ) {
        guard #available(macOS 26.0, *) else {
            return
        }
        if let glass = glassView as? NSGlassEffectView {
            glass.style = NativeGlassSurfaceStyle.glassStyle(role: role, status: status)
            glass.tintColor = NativeGlassSurfaceStyle.tintColor(status: status, readability: readability)
            glass.alphaValue = 1
        } else if let effect = glassView as? NSVisualEffectView {
            effect.alphaValue = readability.materialAlpha
            effect.appearance = NSAppearance(named: .darkAqua)
        }
        applyOverlay(to: scrimView, role: role, status: status, readability: readability)
    }

    func updateAppearance(_ descriptor: NativeGlassBackplateDescriptor) {
        updateAppearance(
            role: descriptor.role,
            status: descriptor.status,
            readability: descriptor.readability
        )
    }

    func updateCornerRadius(_ cornerRadius: CGFloat) {
        if #available(macOS 26.0, *),
           let glass = glassView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else if let effect = glassView as? NSVisualEffectView {
            effect.layer?.cornerRadius = cornerRadius
        }
        scrimView?.cornerRadius = cornerRadius
    }

    func updateCornerRadius(_ descriptor: NativeGlassBackplateDescriptor) {
        updateCornerRadius(descriptor.cornerRadius)
    }

    private func remove() {
        glassView?.removeFromSuperview()
        glassView = nil
        scrimView?.removeFromSuperview()
        scrimView = nil
    }

    private func applyOverlay(
        to scrim: GlassScrimView?,
        role: GlassSurfaceRole,
        status: HUDStatusTone,
        readability: GlassReadabilityStyle
    ) {
        guard let scrim else { return }
        scrim.color = NativeGlassSurfaceStyle.overlayColor(status: status, readability: readability)
        scrim.topSheenAlpha = NativeGlassSurfaceStyle.topSheenAlpha(role: role, status: status)
        scrim.bottomShadeAlpha = NativeGlassSurfaceStyle.bottomShadeAlpha(role: role, status: status)
        scrim.innerRimAlpha = NativeGlassSurfaceStyle.innerRimAlpha(status: status, role: role)
    }

    private func pinToOwner(_ view: NSView, owner: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: owner.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: owner.trailingAnchor),
            view.topAnchor.constraint(equalTo: owner.topAnchor),
            view.bottomAnchor.constraint(equalTo: owner.bottomAnchor)
        ])
    }
}
