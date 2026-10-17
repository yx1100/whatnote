import AppKit

@MainActor
protocol StickyToolbarDelegate: AnyObject {
    func didChooseColor(_ color: NoteColor)
    func didTapArrange()
    func didBeginToolbarDrag(with event: NSEvent)
    func didBeginLockDrag(with event: NSEvent)
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
    func didTapLock()
    func didTapComplete()
}

/// The top strip is the drag handle. It holds three glass capsules:
/// complete on the left, colors and note actions (new, lock, pin, arrange) on the right.
/// A locked note shows only the note actions.
final class StickyToolbarView: NSView {
    weak var delegate: StickyToolbarDelegate?
    private let arrangeButton: NoteToolButton
    private let newButton: NoteToolButton
    private let pinButton: NoteToolButton
    private let lockButton: NoteToolButton
    private let completeButton: NoteToolButton
    private let colorButtons: [ColorDotButton]
    private let leadingCapsule: GlassCapsuleView
    private let colorCapsule: GlassCapsuleView
    private let actionCapsule: GlassCapsuleView

    init(color: NoteColor, isPinned: Bool, isLocked: Bool = false) {
        arrangeButton = NoteToolButton(
            symbol: "square.grid.2x2",
            tip: "排列便签",
            action: #selector(StickyToolbarView.arrangeNotes)
        )
        newButton = NoteToolButton(symbol: "plus", tip: "新建便签", action: #selector(StickyToolbarView.newNote))
        pinButton = NoteToolButton(symbol: "pin", tip: "置顶", action: #selector(StickyToolbarView.togglePin))
        lockButton = NoteToolButton(symbol: "lock.open", tip: "锁定", action: #selector(StickyToolbarView.toggleLock))
        completeButton = NoteToolButton(
            symbol: "checkmark",
            tip: "完成",
            action: #selector(StickyToolbarView.completeNoteButton)
        )
        colorButtons = NoteColor.allCases.map { ColorDotButton(color: $0) }
        leadingCapsule = GlassCapsuleView(views: [completeButton])
        colorCapsule = GlassCapsuleView(views: colorButtons, horizontalPadding: 5)
        actionCapsule = GlassCapsuleView(
            views: [newButton, lockButton, pinButton, arrangeButton],
            horizontalPadding: 3,
            spacing: 2
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for button in [arrangeButton, newButton, lockButton, pinButton, completeButton] {
            button.target = self
        }
        for button in colorButtons {
            button.target = self
            button.action = #selector(selectColor(_:))
        }

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
        update(isLocked: isLocked)
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
        lockButton.accentColor = color.accent
    }

    /// A locked note hides what would change it: the complete button and the colors. The
    /// buttons left lose their glass, like the rest of the flat note.
    func update(isLocked: Bool) {
        lockButton.setSymbol(isLocked ? "lock.fill" : "lock.open", tip: isLocked ? "解锁" : "锁定")
        lockButton.isActive = isLocked
        leadingCapsule.isHidden = isLocked
        colorCapsule.isHidden = isLocked
        actionCapsule.isFlat = isLocked
        // The lock button is the one handle that moves a locked note.
        lockButton.onBeginDrag = isLocked ? { [weak self] event in self?.delegate?.didBeginLockDrag(with: event) } : nil
    }

    @objc private func selectColor(_ sender: ColorDotButton) { delegate?.didChooseColor(sender.noteColor) }
    @objc private func arrangeNotes() { delegate?.didTapArrange() }
    @objc private func newNote() { delegate?.didTapNew() }
    @objc private func togglePin() { delegate?.didTapPin() }
    @objc private func toggleLock() { delegate?.didTapLock() }
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
            tip: "无序列表（⌘7）",
            action: #selector(StickyFormattingFooterView.toggleBullet)
        )
        orderedButton = NoteToolButton(
            symbol: "list.number",
            fallbackSymbol: "list.bullet",
            tip: "有序列表（⌘8）",
            action: #selector(StickyFormattingFooterView.toggleOrdered)
        )
        todoButton = NoteToolButton(
            symbol: "checklist",
            fallbackSymbol: "checkmark.circle",
            tip: "任务列表（⌘9）",
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
