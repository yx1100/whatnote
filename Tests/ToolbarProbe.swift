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
        let expected = ["完成", "粉色", "黄色", "蓝色", "绿色", "新建便签", "置顶", "排列便签"]
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
            "项目符号列表（⌘7）",
            "编号列表（⌘8）",
            "核对清单（⌘9）",
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
    func didTapComplete() {}
}
