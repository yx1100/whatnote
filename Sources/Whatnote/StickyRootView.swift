import AppKit

/// A scroller without the white track that "always show scroll bars" draws, so the note's
/// color shows behind the knob.
final class NoteScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

/// A note: colored paper whose text scrolls underneath two floating glass bars.
final class StickyRootView: NSView {
    let toolbar: StickyToolbarView
    let footer = StickyFormattingFooterView()
    let textView = StickyTextView()
    let scrollView = NSScrollView()
    private let noteLayoutManager = NoteLayoutManager()
    private var hasScrolledToTop = false
    private var color: NoteColor
    private var isLocked = false

    init(note: StickyNote) {
        color = note.color
        toolbar = StickyToolbarView(color: note.color, isPinned: note.isPinned, isLocked: note.isLocked)
        super.init(frame: .zero)
        // Notes are paper-colored in both light and dark mode, so keep light controls and text.
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = NoteScroller()
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        updateScrollInsets(isLocked: note.isLocked)

        // TextKit 1 with a layout manager that draws to-do checkboxes; TextKit 1 also sizes image attachments reliably.
        _ = textView.layoutManager
        textView.textContainer?.replaceLayoutManager(noteLayoutManager)
        textView.isRichText = true
        textView.importsGraphics = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.allowsUndo = true
        textView.font = NoteAppearance.bodyFont()
        textView.textColor = NoteAppearance.textColor
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // The extra height leaves room for a code block's background above the first line.
        textView.textContainerInset = NSSize(width: 14, height: 2 + CodeBlock.verticalPadding)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel("便签内容")
        if let restored = RichTextCodec.decode(note.richTextData) {
            textView.textStorage?.setAttributedString(restored)
            if let storage = textView.textStorage {
                NoteAppearance.repairFonts(in: storage)
                NoteImages.fitAttachments(in: storage)
            }
        } else {
            textView.string = note.text
        }
        textView.typingAttributes = [
            .font: NoteAppearance.bodyFont(),
            .foregroundColor: NoteAppearance.textColor
        ]
        scrollView.documentView = textView

        addSubview(scrollView)
        addSubview(toolbar)
        addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            footer.centerXAnchor.constraint(equalTo: centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -NoteAppearance.barMargin)
        ])
        updateColor(note.color)
        updateLock(note.isLocked)
        layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // Start with the first line just below the top bar.
        guard !hasScrolledToTop, scrollView.contentView.bounds.height > 0 else { return }
        hasScrolledToTop = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -NoteAppearance.topBarHeight))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Locked: the text can be read, scrolled and copied but not changed, the formatting bar
    /// goes away, and the paper turns flat, rounder and a little see-through.
    func updateLock(_ isLocked: Bool) {
        self.isLocked = isLocked
        textView.isLocked = isLocked
        layer?.cornerRadius = isLocked ? NoteAppearance.lockedCornerRadius : NoteAppearance.cornerRadius
        layer?.borderWidth = isLocked ? 0 : 0.5
        applyPaperColor()
        footer.isHidden = isLocked
        updateScrollInsets(isLocked: isLocked)
        toolbar.update(isLocked: isLocked)
    }

    /// Text scrolls under the top bar and the formatting bar; a locked note has no formatting
    /// bar, so nothing is reserved below the text and short text does not scroll.
    private func updateScrollInsets(isLocked: Bool) {
        let insets = NSEdgeInsets(
            top: NoteAppearance.topBarHeight,
            left: 0,
            bottom: isLocked ? 0 : NoteAppearance.bottomBarHeight,
            right: 0
        )
        scrollView.contentInsets = insets
        scrollView.scrollerInsets = insets
    }

    func updateColor(_ color: NoteColor) {
        self.color = color
        applyPaperColor()
        footer.updateAccent(color.accent)
        noteLayoutManager.checkboxAccent = color.accent
        textView.needsDisplay = true
    }

    private func applyPaperColor() {
        let alpha = isLocked ? NoteAppearance.lockedPaperAlpha : 1
        layer?.backgroundColor = color.background.withAlphaComponent(alpha).cgColor
    }
}
