import AppKit

/// Shows a completed note's full content beside the 已完成的便签 popover while the mouse rests
/// on its row. The preview appears after a short pause, follows the mouse from row to row
/// without a delay, and goes away when the mouse leaves the list.
@MainActor
final class HistoryPreviewController {
    static let width: CGFloat = 300
    static let maximumHeight: CGFloat = 380
    static let showDelay: TimeInterval = 0.35
    static let hideDelay: TimeInterval = 0.15

    private var panel: NSPanel?
    /// Bumped whenever the mouse moves on, so a delayed show or hide that is no longer
    /// wanted does nothing.
    private var generation = 0
    private(set) var shownNoteID: UUID?

    var isShowing: Bool { panel?.isVisible == true }
    /// Where the preview is, while it is showing.
    var shownFrame: NSRect? { isShowing ? panel?.frame : nil }

    /// The note under the mouse and its row, or nil when the mouse has left the rows.
    func hover(_ note: StickyNote?, row: NSView?) {
        generation += 1
        guard let note, let row else {
            schedule(after: Self.hideDelay) { [weak self] in self?.hide() }
            return
        }
        if isShowing {
            show(note, beside: row)
        } else {
            schedule(after: Self.showDelay) { [weak self, weak row] in
                guard let row else { return }
                self?.show(note, beside: row)
            }
        }
    }

    func hide() {
        generation += 1
        panel?.orderOut(nil)
        shownNoteID = nil
    }

    func show(_ note: StickyNote, beside row: NSView) {
        guard let anchor = row.window else { return }
        let visible = anchor.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor.frame
        let content = HistoryPreviewView(
            note: note,
            width: Self.width,
            maximumHeight: min(Self.maximumHeight, visible.height - 16)
        )
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        let rowRect = anchor.convertToScreen(row.convert(row.bounds, to: nil))
        // The popover's own content, not its window, which has room around it for the arrow.
        let popoverRect = anchor.contentView.map { anchor.convertToScreen($0.convert($0.bounds, to: nil)) } ?? anchor.frame
        // Size the panel first: a content view takes on the size of the window it is put in.
        panel.setFrame(
            Self.frame(size: content.frame.size, rowRect: rowRect, anchor: popoverRect, visible: visible),
            display: false
        )
        panel.contentView = content
        panel.level = NSWindow.Level(rawValue: max(anchor.level.rawValue, NSWindow.Level.popUpMenu.rawValue))
        panel.alphaValue = 1
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        shownNoteID = note.id
    }

    /// Beside the popover, preferably on its left, with its top level with the row's top,
    /// and kept on screen.
    static func frame(size: NSSize, rowRect: NSRect, anchor: NSRect, visible: NSRect) -> NSRect {
        let gap: CGFloat = 6
        var x = anchor.minX - gap - size.width
        if x < visible.minX { x = anchor.maxX + gap }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = min(max(rowRect.maxY - size.height, visible.minY), visible.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let scheduled = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == scheduled else { return }
            action()
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Only a preview: clicks go to whatever is underneath.
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.appearance = NSAppearance(named: .aqua)
        return panel
    }
}

/// A completed note drawn the way it looks on the desktop: its paper color, text, checkboxes,
/// dividers, code blocks and images. A note taller than the preview fades out at the bottom.
@MainActor
final class HistoryPreviewView: NSView {
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 12
    private static let fadeHeight: CGFloat = 44

    let textView: NSTextView
    let isTruncated: Bool

    init(note: StickyNote, width: CGFloat, maximumHeight: CGFloat) {
        let storage = NSTextStorage(attributedString: Self.text(for: note))
        NoteImages.fitAttachments(in: storage)
        let layoutManager = NoteLayoutManager()
        layoutManager.checkboxAccent = note.color.accent
        storage.addLayoutManager(layoutManager)
        let textWidth = width - 2 * Self.horizontalPadding
        let container = NSTextContainer(size: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let textHeight = ceil(layoutManager.usedRect(for: container).height)
        let fullHeight = textHeight + 2 * Self.verticalPadding
        isTruncated = fullHeight > maximumHeight
        let height = min(fullHeight, maximumHeight)
        textView = NSTextView(
            frame: NSRect(
                x: Self.horizontalPadding,
                y: height - Self.verticalPadding - textHeight,
                width: textWidth,
                height: textHeight
            ),
            textContainer: container
        )
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false

        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.backgroundColor = note.color.background.cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        addSubview(textView)
        if isTruncated {
            addSubview(Self.fadeView(width: width, color: note.color.background))
        }
    }

    required init?(coder: NSCoder) { nil }

    /// The note's rich text as saved, or its plain text in the body style.
    static func text(for note: StickyNote) -> NSAttributedString {
        let text: NSMutableAttributedString
        if let restored = RichTextCodec.decode(note.richTextData) {
            text = NSMutableAttributedString(attributedString: restored)
            NoteAppearance.upgradeLegacyFontSizes(in: text, from: note.fontGeneration)
        } else {
            text = NSMutableAttributedString(string: note.text)
        }
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.font, in: whole) { value, range, _ in
            if value == nil { text.addAttribute(.font, value: NoteAppearance.bodyFont(), range: range) }
        }
        text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: NoteAppearance.textColor, range: range) }
        }
        return text
    }

    private static func fadeView(width: CGFloat, color: NSColor) -> NSView {
        let fade = NSView(frame: NSRect(x: 0, y: 0, width: width, height: fadeHeight))
        fade.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = fade.bounds
        // Bottom (opaque) to top (clear).
        gradient.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        fade.layer?.addSublayer(gradient)
        return fade
    }
}
