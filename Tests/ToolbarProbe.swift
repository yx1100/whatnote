import AppKit

@main
struct ToolbarProbe {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let toolbar = StickyToolbarView(color: .yellow, isPinned: false)
        let delegate = ToolbarDelegateProbe()
        toolbar.delegate = delegate
        guard toolbar.acceptsFirstMouse(for: nil) else { exit(11) }

        let buttons = descendants(of: toolbar).compactMap { $0 as? NSButton }
        let labels = buttons.compactMap { $0.accessibilityLabel() }
        let expected = ["完成", "粉色", "黄色", "蓝色", "绿色", "新建便签", "锁定", "置顶", "排列便签"]
        guard labels == expected else { exit(2) }
        guard descendants(of: toolbar).filter({ $0 is GlassCapsuleView }).count == 3 else { exit(1) }

        let colorButtons = buttons.compactMap { $0 as? ColorDotButton }
        guard colorButtons.map(\.noteColor) == NoteColor.allCases else { exit(3) }
        guard let selectedColor = colorButtons.first(where: { $0.selectedColor }),
              selectedColor.noteColor == .yellow,
              colorButtons.filter({ $0.selectedColor }).count == 1,
              colorButtons.filter({ !$0.selectedColor }).allSatisfy({
                  $0.dotDiameter < selectedColor.dotDiameter && $0.ringWidth < selectedColor.ringWidth
              }) else { exit(4) }

        guard let arrange = buttons.first(where: { $0.accessibilityLabel() == "排列便签" }) else { exit(5) }
        arrange.performClick(nil)
        guard delegate.arrangeCount == 1 else { exit(6) }
        guard !labels.contains("历史便签") else { exit(12) }

        toolbar.update(color: .pink, isPinned: true)
        guard let pin = buttons.first(where: { $0.accessibilityLabel() == "取消置顶" }) as? NoteToolButton,
              pin.isActive,
              colorButtons.first(where: { $0.selectedColor })?.noteColor == .pink else { exit(14) }

        // The lock sits next to the pin; locking hides the complete button and the colors.
        guard let lock = buttons.first(where: { $0.accessibilityLabel() == "锁定" }) as? NoteToolButton else { exit(23) }
        lock.performClick(nil)
        guard delegate.lockCount == 1 else { exit(24) }
        toolbar.update(isLocked: true)
        let capsules = descendants(of: toolbar).compactMap { $0 as? GlassCapsuleView }
        guard lock.accessibilityLabel() == "解锁", lock.isActive,
              capsules.filter(\.isHidden).count == 2 else { exit(25) }
        guard lock.onBeginDrag != nil else { exit(31) }
        let hiddenWhenLocked = buttons.filter(\.isHidden).compactMap { $0.accessibilityLabel() }
        guard hiddenWhenLocked == ["新建便签", "排列便签"] else { exit(32) }
        toolbar.update(isLocked: false)
        guard lock.onBeginDrag == nil, buttons.allSatisfy({ !$0.isHidden }), lock.accessibilityLabel() == "锁定", !lock.isActive,
              capsules.allSatisfy({ !$0.isHidden }) else { exit(26) }

        // A locked note can be read but not edited, and has no formatting bar.
        var lockedNote = StickyNote.fresh()
        lockedNote.text = "☐ 待办"
        lockedNote.isLocked = true
        let lockedRoot = StickyRootView(note: lockedNote)
        guard !lockedRoot.textView.isEditable, lockedRoot.textView.isSelectable, lockedRoot.footer.isHidden else { exit(27) }
        // A locked note whose text fits does not scroll; the same text in an open note still leaves room under the formatting bar.
        func scrollRange(of root: StickyRootView) -> CGFloat {
            let host = NSWindow(contentRect: NSRect(origin: .zero, size: NoteAppearance.lockedSize), styleMask: [.borderless], backing: .buffered, defer: false)
            host.contentView = root
            root.frame = NSRect(origin: .zero, size: NoteAppearance.lockedSize)
            root.layoutSubtreeIfNeeded()
            let insets = root.scrollView.contentInsets
            return root.textView.frame.height + insets.top + insets.bottom - root.scrollView.contentView.bounds.height
        }
        var shortNote = StickyNote.fresh()
        shortNote.text = (1...10).map { "第\($0)行" }.joined(separator: "\n")
        shortNote.isLocked = true
        let shortLocked = StickyRootView(note: shortNote)
        guard scrollRange(of: shortLocked) <= 0.5 else { exit(34) }
        var shortOpen = shortNote
        shortOpen.isLocked = false
        guard scrollRange(of: StickyRootView(note: shortOpen)) > 0.5 else { exit(36) }
        // The wheel does nothing on a locked note whose text fits.
        func wheelMoves(_ root: StickyRootView) -> Bool {
            _ = scrollRange(of: root)
            let before = root.scrollView.contentView.bounds.origin.y
            for delta in [Int32(-120), 120] {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0),
                      let event = NSEvent(cgEvent: cg) else { exit(37) }
                root.scrollView.scrollWheel(with: event)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                if root.scrollView.contentView.bounds.origin.y != before { return true }
            }
            return false
        }
        guard !wheelMoves(shortLocked) else { exit(38) }
        var longNote = shortNote
        longNote.text = (0..<40).map { "第\($0)行" }.joined(separator: "\n")
        guard scrollRange(of: StickyRootView(note: longNote)) > 0.5 else { exit(35) }

        // Locked paper is flat (no border), rounder and a little see-through; unlocking restores it.
        let lockedPaper = lockedRoot.layer
        guard lockedPaper?.cornerRadius == NoteAppearance.lockedCornerRadius, lockedPaper?.borderWidth == 0,
              lockedPaper?.backgroundColor?.alpha == NoteAppearance.lockedPaperAlpha,
              descendants(of: lockedRoot.toolbar).compactMap({ $0 as? GlassCapsuleView }).filter(\.isFlat).count == 1 else { exit(29) }
        // Typed text never takes the small symbol font of the to-do circle.
        lockedRoot.textView.typingAttributes = [.font: NSFont(name: "AppleSymbols", size: 16)!]
        guard !NoteAppearance.isSymbolFont(lockedRoot.textView.typingAttributes[.font] as? NSFont) else { exit(33) }
        lockedRoot.updateLock(false)
        guard lockedRoot.textView.isEditable, !lockedRoot.footer.isHidden else { exit(28) }
        let openPaper = lockedRoot.layer
        guard openPaper?.cornerRadius == NoteAppearance.cornerRadius, openPaper?.borderWidth == 0.5,
              openPaper?.backgroundColor?.alpha == 1,
              descendants(of: lockedRoot.toolbar).compactMap({ $0 as? GlassCapsuleView }).allSatisfy({ !$0.isFlat }) else { exit(30) }

        // Empty space between the capsules is the drag handle.
        toolbar.frame = NSRect(x: 0, y: 0, width: 300, height: NoteAppearance.topBarHeight)
        toolbar.layoutSubtreeIfNeeded()
        guard toolbar.hitTest(NSPoint(x: 70, y: NoteAppearance.topBarHeight / 2)) === toolbar else { exit(8) }

        let root = StickyRootView(note: .fresh())
        guard root.textView.font?.pointSize == NoteAppearance.bodyFontSize else { exit(9) }
        guard root.textView.layoutManager is NoteLayoutManager else { exit(17) }
        guard !descendants(of: root).contains(where: { ($0 as? NSTextField)?.stringValue.contains("保存") == true }) else { exit(15) }

        let footer = StickyFormattingFooterView()
        footer.delegate = delegate
        let formattingButtons = descendants(of: footer).compactMap { $0 as? NoteToolButton }
        guard formattingButtons.compactMap({ $0.accessibilityLabel() }) == [
            "粗体（⌘B）",
            "无序列表（⌘7）",
            "有序列表（⌘8）",
            "任务列表（⌘9）",
            "分隔线",
            "代码块",
            "插入图片"
        ] else { exit(13) }
        formattingButtons[2].performClick(nil)
        formattingButtons[3].performClick(nil)
        formattingButtons[4].performClick(nil)
        formattingButtons[5].performClick(nil)
        guard delegate.dividerCount == 1, delegate.codeBlockCount == 1 else { exit(21) }
        guard delegate.orderedCount == 1, delegate.todoCount == 1 else { exit(10) }
        footer.updateFormatting(isBold: true, isBulletList: false, isOrderedList: true, isTodoItem: false)
        guard formattingButtons.map(\.isActive) == [true, false, true, false, false, false, false] else { exit(16) }
        footer.updateFormatting(isBold: false, isBulletList: false, isOrderedList: false, isTodoItem: false, isCodeBlock: true)
        guard formattingButtons.map(\.isActive) == [false, false, false, false, false, true, false] else { exit(22) }

        // To-do markers are drawn as circles and toggle when clicked.
        var todoNote = StickyNote.fresh()
        todoNote.text = "☐ 买牛奶\n普通一行"
        let todoRoot = StickyRootView(note: todoNote)
        let textView = todoRoot.textView
        textView.frame = NSRect(origin: .zero, size: NoteAppearance.defaultSize)
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { exit(18) }
        layoutManager.ensureLayout(for: container)
        let origin = textView.textContainerOrigin
        let checkbox = TodoCheckbox.rect(forGlyphAt: 0, layoutManager: layoutManager)
        guard textView.todoMarkerIndex(at: NSPoint(x: checkbox.midX + origin.x, y: checkbox.midY + origin.y)) == 0 else { exit(19) }
        let plainGlyph = layoutManager.glyphIndexForCharacter(at: 6)
        let plainRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: plainGlyph, length: 1), in: container)
        guard textView.todoMarkerIndex(at: NSPoint(x: plainRect.midX + origin.x, y: plainRect.midY + origin.y)) == nil else { exit(20) }
        if let bitmap = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) {
            textView.cacheDisplay(in: textView.bounds, to: bitmap)
        }

        print("toolbar layout: pass")
    }

    @MainActor
    private static func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

@MainActor
private final class ToolbarDelegateProbe: StickyToolbarDelegate {
    var arrangeCount = 0
    var todoCount = 0
    var orderedCount = 0
    var dividerCount = 0
    var codeBlockCount = 0
    var lockCount = 0

    func didChooseColor(_ color: NoteColor) {}
    func didTapArrange() { arrangeCount += 1 }
    func didBeginToolbarDrag(with event: NSEvent) {}
    func didTapBold() {}
    func didTapBulletList() {}
    func didTapOrderedList() { orderedCount += 1 }
    func didTapTodo() { todoCount += 1 }
    func didTapDivider() { dividerCount += 1 }
    func didTapCodeBlock() { codeBlockCount += 1 }
    func didTapLink() {}
    func didTapImage() {}
    func didTapNew() {}
    func didTapPin() {}
    func didTapLock() { lockCount += 1 }
    func didBeginLockDrag(with event: NSEvent) {}
    func didTapComplete() {}
}
