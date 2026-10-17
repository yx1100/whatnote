import AppKit

/// A group of controls floating above the note. macOS 26 and later draw it with
/// Liquid Glass; earlier systems get a frosted material of the same shape.
final class GlassCapsuleView: NSView {
    let stack = NSStackView()
    private let background: NSView
    /// Flat: the buttons stay, the glass behind them goes.
    var isFlat = false {
        didSet { background.isHidden = isFlat }
    }

    init(views: [NSView], horizontalPadding: CGFloat = 1, spacing: CGFloat = 0) {
        background = Self.makeBackground(cornerRadius: NoteAppearance.capsuleHeight / 2)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: horizontalPadding, bottom: 0, right: horizontalPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Hug the buttons so the capsule never stretches into free space.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        views.forEach { stack.addArrangedSubview($0) }
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NoteAppearance.capsuleHeight),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Liquid Glass needs the macOS 26 SDK (Swift 6.2 or later) to build and macOS 26 to run.
    private static func makeBackground(cornerRadius: CGFloat) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        }
        #endif
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        return material
    }
}

/// Icon button for the glass bars. Active formats show a solid accent-colored disc
/// with a white symbol; hovering shows a faint disc.
final class NoteToolButton: NSButton {
    static let size: CGFloat = 28

    var isActive = false { didSet { refreshAppearance() } }
    var accentColor: NSColor = NoteAppearance.iconColor { didSet { refreshAppearance() } }
    private var isHovered = false { didSet { needsDisplay = true } }

    /// Symbols at the same point size differ in width; a wide one can use a smaller `pointSize`.
    private var pointSize: CGFloat
    private var glyphLift: CGFloat = 0

    init(symbol: String, fallbackSymbol: String? = nil, tip: String, pointSize: CGFloat = 13, action: Selector) {
        self.pointSize = pointSize
        super.init(frame: .zero)
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        self.action = action
        setSymbol(symbol, fallbackSymbol: fallbackSymbol, tip: tip)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size)
        ])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// When set, pressing the button and dragging calls this with the drag event instead of
    /// clicking; a press without a drag still clicks.
    var onBeginDrag: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let onBeginDrag else {
            super.mouseDown(with: event)
            return
        }
        let start = event.locationInWindow
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { sendAction(action, to: target) }
                return
            }
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 3 {
                onBeginDrag(next)
                return
            }
        }
    }

    /// `lift` moves the glyph up: a filled padlock has its weight in the body, which looks low when the
    /// outline is centered.
    func setSymbol(_ symbol: String, fallbackSymbol: String? = nil, tip: String, pointSize: CGFloat? = nil, lift: CGFloat = 0) {
        if let pointSize { self.pointSize = pointSize }
        let configuration = NSImage.SymbolConfiguration(pointSize: self.pointSize, weight: .medium)
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            ?? fallbackSymbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: tip) }
        image = symbolImage?.withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 14, height: 14))
        glyphLift = lift
        toolTip = tip
        setAccessibilityLabel(tip)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    static let discDiameter: CGFloat = 24

    override func draw(_ dirtyRect: NSRect) {
        let disc = NSBezierPath(ovalIn: NSRect(
            x: bounds.midX - Self.discDiameter / 2,
            y: bounds.midY - Self.discDiameter / 2,
            width: Self.discDiameter,
            height: Self.discDiameter
        ))
        if isActive {
            accentColor.setFill()
            disc.fill()
        } else if isHovered, isEnabled {
            NSColor.black.withAlphaComponent(0.07).setFill()
            disc.fill()
        }
        NSGraphicsContext.saveGraphicsState()
        let shift = NSAffineTransform()
        shift.translateX(by: 0, yBy: isFlipped ? -glyphLift : glyphLift)
        shift.concat()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func refreshAppearance() {
        contentTintColor = isActive ? .white : NoteAppearance.iconColor
        needsDisplay = true
    }
}

/// Color choice: a filled dot with a deeper ring of the same hue.
/// The current color is drawn larger with a heavier ring.
final class ColorDotButton: NSButton {
    let noteColor: NoteColor
    var selectedColor = false {
        didSet {
            state = selectedColor ? .on : .off
            setAccessibilityValue(selectedColor ? 1 : 0)
            needsDisplay = true
        }
    }

    init(color: NoteColor) {
        noteColor = color
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.radio)
        title = ""
        focusRingType = .none
        toolTip = color.title
        setAccessibilityLabel(color.title)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 21, height: NoteToolButton.size) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var dotDiameter: CGFloat { selectedColor ? 17 : 13 }
    var ringWidth: CGFloat { selectedColor ? 1.75 : 1 }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSRect(
            x: bounds.midX - dotDiameter / 2,
            y: bounds.midY - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        )
        let dot = NSBezierPath(ovalIn: circle.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
        noteColor.background.setFill()
        dot.fill()
        noteColor.accent.setStroke()
        dot.lineWidth = ringWidth
        dot.stroke()
    }
}
