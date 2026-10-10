import AppKit

@MainActor
protocol StickyToolbarDelegate: AnyObject {
    func didChooseColor(_ color: NoteColor)
    func didTapArrange()
    func didBeginToolbarDrag(with event: NSEvent)
    func didTapBold()
    func didTapBulletList()
    func didTapOrderedList()
    func didTapTodo()
    func didTapDivider()
    func didTapCodeBlock()
    func didTapLink()
    func didTapImage()
    func didTapNew()
    func didTapPin()
    func didTapComplete()
}

/// The top strip is the drag handle. It holds three glass capsules:
/// complete on the left, colors and note actions (new, pin, arrange) on the right.
final class StickyToolbarView: NSView {
    weak var delegate: StickyToolbarDelegate?
    private let arrangeButton: NoteToolButton
    private let newButton: NoteToolButton
    private let pinButton: NoteToolButton
    private let completeButton: NoteToolButton
    private let colorButtons: [ColorDotButton]

    init(color: NoteColor, isPinned: Bool) {
        arrangeButton = NoteToolButton(
            symbol: "square.grid.2x2",
            tip: "排列便签",
            action: #selector(StickyToolbarView.arrangeNotes)
        )
        newButton = NoteToolButton(symbol: "plus", tip: "新建便签", action: #selector(StickyToolbarView.newNote))
        pinButton = NoteToolButton(symbol: "pin", tip: "置顶", action: #selector(StickyToolbarView.togglePin))
        completeButton = NoteToolButton(
            symbol: "checkmark",
            tip: "完成",
            action: #selector(StickyToolbarView.completeNoteButton)
        )
        colorButtons = NoteColor.allCases.map { ColorDotButton(color: $0) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for button in [arrangeButton, newButton, pinButton, completeButton] {
            button.target = self
        }
        for button in colorButtons {
            button.target = self
            button.action = #selector(selectColor(_:))
        }

        let leadingCapsule = GlassCapsuleView(views: [completeButton])
        let colorCapsule = GlassCapsuleView(views: colorButtons, horizontalPadding: 5)
        let actionCapsule = GlassCapsuleView(views: [newButton, pinButton, arrangeButton], horizontalPadding: 3, spacing: 2)
        for capsule in [leadingCapsule, colorCapsule, actionCapsule] {
            addSubview(capsule)
        }

        let margin = NoteAppearance.barMargin
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NoteAppearance.topBarHeight),
            leadingCapsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            leadingCapsule.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            actionCapsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            actionCapsule.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            colorCapsule.trailingAnchor.constraint(equalTo: actionCapsule.leadingAnchor, constant: -6),
            colorCapsule.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            colorCapsule.leadingAnchor.constraint(greaterThanOrEqualTo: leadingCapsule.trailingAnchor, constant: 6)
        ])
        update(color: color, isPinned: isPinned)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Everything that is not a control drags the note.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var candidate: NSView? = hit
        while let view = candidate, view !== self {
            if view is NSControl { return hit }
            candidate = view.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.didBeginToolbarDrag(with: event)
    }

    func update(color: NoteColor, isPinned: Bool) {
        colorButtons.forEach { $0.selectedColor = $0.noteColor == color }
        pinButton.setSymbol(isPinned ? "pin.fill" : "pin", tip: isPinned ? "取消置顶" : "置顶")
        pinButton.accentColor = color.accent
        pinButton.isActive = isPinned
    }

    @objc private func selectColor(_ sender: ColorDotButton) { delegate?.didChooseColor(sender.noteColor) }
    @objc private func arrangeNotes() { delegate?.didTapArrange() }
    @objc private func newNote() { delegate?.didTapNew() }
    @objc private func togglePin() { delegate?.didTapPin() }
    @objc private func completeNoteButton() { delegate?.didTapComplete() }
}

/// Formatting bar floating at the bottom of the note.
final class StickyFormattingFooterView: NSView {
    weak var delegate: StickyToolbarDelegate?
    private let boldButton: NoteToolButton
    private let bulletButton: NoteToolButton
    private let orderedButton: NoteToolButton
    private let todoButton: NoteToolButton
    private let dividerButton: NoteToolButton
    private let codeButton: NoteToolButton
    private let imageButton: NoteToolButton

    private var buttons: [NoteToolButton] {
        [boldButton, bulletButton, orderedButton, todoButton, dividerButton, codeButton, imageButton]
    }

    override init(frame frameRect: NSRect) {
        boldButton = NoteToolButton(
            symbol: "bold",
            tip: "粗体（⌘B）",
            action: #selector(StickyFormattingFooterView.toggleBold)
        )
        bulletButton = NoteToolButton(
            symbol: "list.bullet",
            tip: "项目符号列表（⌘7）",
            action: #selector(StickyFormattingFooterView.toggleBullet)
        )
        orderedButton = NoteToolButton(
            symbol: "list.number",
            fallbackSymbol: "list.bullet",
            tip: "编号列表（⌘8）",
            action: #selector(StickyFormattingFooterView.toggleOrdered)
        )
        todoButton = NoteToolButton(
            symbol: "checklist",
            fallbackSymbol: "checkmark.circle",
            tip: "核对清单（⌘9）",
            action: #selector(StickyFormattingFooterView.toggleTodo)
        )
        dividerButton = NoteToolButton(
            symbol: "minus",
            tip: "分隔线",
            action: #selector(StickyFormattingFooterView.insertDivider)
        )
        codeButton = NoteToolButton(
            symbol: "chevron.left.forwardslash.chevron.right",
            fallbackSymbol: "curlybraces",
            tip: "代码块",
            // The wide </> glyph looks larger than the other icons at 13 pt.
            pointSize: 11,
            action: #selector(StickyFormattingFooterView.toggleCodeBlock)
        )
        imageButton = NoteToolButton(
            symbol: "photo",
            tip: "插入图片",
            action: #selector(StickyFormattingFooterView.insertImage)
        )
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        buttons.forEach { $0.target = self }
        let capsule = GlassCapsuleView(views: buttons, horizontalPadding: 3, spacing: 2)
        addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func updateFormatting(isBold: Bool, isBulletList: Bool, isOrderedList: Bool, isTodoItem: Bool, isCodeBlock: Bool = false) {
        boldButton.isActive = isBold
        codeButton.isActive = isCodeBlock
        bulletButton.isActive = isBulletList
        orderedButton.isActive = isOrderedList
        todoButton.isActive = isTodoItem
    }

    func updateAccent(_ color: NSColor) {
        buttons.forEach { $0.accentColor = color }
    }

    @objc private func toggleBold() { delegate?.didTapBold() }
    @objc private func toggleBullet() { delegate?.didTapBulletList() }
    @objc private func toggleOrdered() { delegate?.didTapOrderedList() }
    @objc private func toggleTodo() { delegate?.didTapTodo() }
    @objc private func insertDivider() { delegate?.didTapDivider() }
    @objc private func toggleCodeBlock() { delegate?.didTapCodeBlock() }
    @objc private func insertImage() { delegate?.didTapImage() }
}

enum StickyEditingShortcut: Equatable {
    case copy, cut, paste, selectAll

    static func command(for modifiers: NSEvent.ModifierFlags, key: String?) -> StickyEditingShortcut? {
        guard modifiers == [.command] else { return nil }
        switch key {
        case "c": return .copy
        case "x": return .cut
        case "v": return .paste
        case "a": return .selectAll
        default: return nil
        }
    }
}

final class StickyTextView: NSTextView {
    var onToggleBold: (() -> Void)?
    var onToggleItalic: (() -> Void)?
    var onToggleChecked: (() -> Void)?
    var onToggleBulletList: (() -> Void)?
    var onToggleOrderedList: (() -> Void)?
    var onToggleTodo: (() -> Void)?
    var onEditLink: (() -> Void)?
    /// Called with the marker's character index when a to-do checkbox is clicked.
    var onToggleTodoMarker: ((Int) -> Void)?
    var onStructuredNewline: (() -> Bool)?
    var onAdjustBulletLevel: ((Int) -> Bool)?
    /// Returns true when it handled the key, e.g. removed a whole to-do marker.
    var onDeleteBackward: (() -> Bool)?
    /// Closes the note, like the 完成 button; used by ⌘W and pressing Esc twice.
    var onCloseNote: (() -> Void)?
    /// Adjusts plain text before it is pasted, e.g. drops a to-do marker pasted mid-line.
    var onPreparePaste: ((String) -> String)?
    private var lastEscapeTimestamp: TimeInterval?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if onToggleTodoMarker != nil,
           let marker = todoMarkerIndex(at: convert(event.locationInWindow, from: nil)) {
            // A quick double click should not flip the item back.
            if event.clickCount == 1 { onToggleTodoMarker?(marker) }
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        if todoMarkerIndex(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }

    /// Character index of the to-do marker whose checkbox is under `point` (view coordinates).
    func todoMarkerIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        var lineGlyphs = NSRange(location: NSNotFound, length: 0)
        _ = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphs)
        guard lineGlyphs.location != NSNotFound else { return nil }
        let markerIndex = layoutManager.characterIndexForGlyph(at: lineGlyphs.location)
        guard TodoMarker.isCompleted(in: storage.string as NSString, at: markerIndex) != nil else { return nil }
        let checkbox = TodoCheckbox.rect(forGlyphAt: lineGlyphs.location, layoutManager: layoutManager)
        return checkbox.insetBy(dx: -4, dy: -4).contains(containerPoint) ? markerIndex : nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == [.command], key == "b" {
            onToggleBold?()
            return true
        }
        if modifiers == [.command], key == "i" {
            onToggleItalic?()
            return true
        }
        // ⌘7 bulleted list, ⌘8 numbered list, ⌘9 checklist, in the order of the footer buttons.
        if modifiers == [.command] {
            switch key {
            case "7":
                onToggleBulletList?()
                return true
            case "8":
                onToggleOrderedList?()
                return true
            case "9":
                onToggleTodo?()
                return true
            default:
                break
            }
        }
        // ⇧⌘U marks checklist items as checked, as in Apple Notes.
        if modifiers == [.command, .shift] {
            switch key {
            case "u":
                onToggleChecked?()
                return true
            default:
                break
            }
        }
        if modifiers == [.command], key == "k" {
            onEditLink?()
            return true
        }
        if modifiers == [.command], key == "w", ClosePreferences.closesOnCommandW() {
            onCloseNote?()
            return true
        }
        if let command = StickyEditingShortcut.command(for: modifiers, key: key) {
            switch command {
            case .copy: copy(nil)
            case .cut: cut(nil)
            case .paste: paste(nil)
            case .selectAll: selectAll(nil)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, handleEscape(event) { return } // 53: Esc
        super.keyDown(with: event)
    }

    /// Two presses of Esc in quick succession close the note. Esc still cancels input-method
    /// composition, and a single press does nothing else in a note.
    private func handleEscape(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty, !hasMarkedText(), ClosePreferences.closesOnDoubleEscape() else { return false }
        if event.isARepeat { return true }
        if let last = lastEscapeTimestamp, event.timestamp - last <= NSEvent.doubleClickInterval {
            lastEscapeTimestamp = nil
            onCloseNote?()
        } else {
            lastEscapeTimestamp = event.timestamp
        }
        return true
    }

    override func insertNewline(_ sender: Any?) {
        if onStructuredNewline?() == true { return }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if onDeleteBackward?() == true { return }
        super.deleteBackward(sender)
    }

    override func insertTab(_ sender: Any?) {
        if onAdjustBulletLevel?(1) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if onAdjustBulletLevel?(-1) == true { return }
        super.insertBacktab(sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let images = NoteImages.images(on: pasteboard)
        if !images.isEmpty, NoteImages.insert(images, into: self) { return }
        let start = selectedRange().location
        if let text = pasteboard.string(forType: .string),
           let prepared = onPreparePaste?(text), prepared != text {
            insertText(prepared, replacementRange: selectedRange())
        } else {
            super.pasteAsPlainText(sender)
        }
        let end = selectedRange().location
        NoteLinks.detectLinks(in: self, range: NSRange(location: start, length: max(0, end - start)))
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let point = convert(sender.draggingLocation, from: nil)
        let dropRange = NSRange(location: characterIndexForInsertion(at: point), length: 0)

        if !fileURLs.isEmpty {
            let imageURLs = NoteImages.imageFileURLs(on: pasteboard)
            if !imageURLs.isEmpty {
                return NoteImages.insert(imageURLs.compactMap(NSImage.init(contentsOf:)), into: self, replacing: dropRange)
            }
            // Other files become links so the note stays small.
            return insertFileLinks(fileURLs, at: dropRange)
        }

        // Images dragged from a browser; rich text drags keep the default behavior.
        let carriesRichText = pasteboard.availableType(from: [.rtf, .rtfd]) != nil
        if !carriesRichText,
           pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty {
            return NoteImages.insert(images, into: self, replacing: dropRange)
        }
        return super.performDragOperation(sender)
    }

    private func insertFileLinks(_ urls: [URL], at range: NSRange) -> Bool {
        guard let storage = textStorage else { return false }
        let insertion = NSMutableAttributedString()
        for (index, url) in urls.enumerated() {
            if index > 0 { insertion.append(NSAttributedString(string: " ", attributes: typingAttributes)) }
            var attributes = typingAttributes
            attributes[.link] = url
            insertion.append(NSAttributedString(string: url.lastPathComponent, attributes: attributes))
        }
        let safeRange = NSRange(location: min(range.location, storage.length), length: 0)
        guard shouldChangeText(in: safeRange, replacementString: insertion.string) else { return false }
        storage.replaceCharacters(in: safeRange, with: insertion)
        setSelectedRange(NSRange(location: safeRange.location + insertion.length, length: 0))
        didChangeText()
        return true
    }
}

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

    init(note: StickyNote) {
        toolbar = StickyToolbarView(color: note.color, isPinned: note.isPinned)
        super.init(frame: .zero)
        // Notes are paper-colored in both light and dark mode, so keep light controls and text.
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.cornerRadius = NoteAppearance.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = NoteScroller()
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        let barInsets = NSEdgeInsets(
            top: NoteAppearance.topBarHeight,
            left: 0,
            bottom: NoteAppearance.bottomBarHeight,
            right: 0
        )
        scrollView.contentInsets = barInsets
        scrollView.scrollerInsets = barInsets

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
                NoteAppearance.upgradeLegacyFontSizes(in: storage)
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
        layer?.borderWidth = 0.5
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

    func updateColor(_ color: NoteColor) {
        layer?.backgroundColor = color.background.cgColor
        footer.updateAccent(color.accent)
        noteLayoutManager.checkboxAccent = color.accent
        textView.needsDisplay = true
    }
}
