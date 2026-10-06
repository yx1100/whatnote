import AppKit

@MainActor
final class StickyWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, StickyToolbarDelegate {
    private var note: StickyNote
    private let rootView: StickyRootView
    private let windowResidency: StickyWindowResidency
    private var isApplyingMarkdown = false
    weak var appController: AppController?
    var isPinned: Bool { note.isPinned }

    init(note: StickyNote) {
        self.note = note
        rootView = StickyRootView(note: note)
        let residentWindow = StickyWindow(
            contentRect: note.frame.rect,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        windowResidency = StickyWindowResidency(residentWindow: residentWindow)
        super.init(window: residentWindow)
        configureWindow(residentWindow)
        residentWindow.contentView = rootView
        rootView.toolbar.delegate = self
        rootView.footer.delegate = self
        rootView.textView.delegate = self
        rootView.textView.onToggleBold = { [weak self] in self?.didTapBold() }
        rootView.textView.onToggleItalic = { [weak self] in
            guard let self else { return }
            RichTextFormatting.toggleItalic(in: self.rootView.textView)
            self.rootView.textView.didChangeText()
        }
        rootView.textView.onToggleChecked = { [weak self] in
            guard let self else { return }
            RichTextFormatting.toggleCheckedState(in: self.rootView.textView)
            self.updateFormattingState()
        }
        rootView.textView.onToggleBulletList = { [weak self] in self?.didTapBulletList() }
        rootView.textView.onToggleOrderedList = { [weak self] in self?.didTapOrderedList() }
        rootView.textView.onToggleTodo = { [weak self] in self?.didTapTodo() }
        rootView.textView.onEditLink = { [weak self] in self?.didTapLink() }
        rootView.textView.onToggleTodoMarker = { [weak self] index in self?.toggleTodoMarker(at: index) }
        rootView.textView.onStructuredNewline = { [weak self] in
            guard let self else { return false }
            return RichTextFormatting.handleStructuredNewline(in: self.rootView.textView)
        }
        rootView.textView.onAdjustBulletLevel = { [weak self] delta in
            guard let self else { return false }
            let changed = RichTextFormatting.adjustBulletLevel(in: self.rootView.textView, delta: delta)
            if changed { self.rootView.textView.didChangeText() }
            return changed
        }
        rootView.textView.onDeleteBackward = { [weak self] in
            guard let self else { return false }
            return RichTextFormatting.handleDividerBackspace(in: self.rootView.textView)
                || RichTextFormatting.handleCodeBackspace(in: self.rootView.textView)
                || RichTextFormatting.handleMarkerBackspace(in: self.rootView.textView)
        }
        rootView.textView.onCloseNote = { [weak self] in self?.didTapComplete() }
        rootView.textView.onPreparePaste = { [weak self] text in
            guard let self else { return text }
            return RichTextFormatting.textForPaste(text, in: self.rootView.textView)
        }
        let repairedBullets = RichTextFormatting.normalizeBulletMarkers(in: rootView.textView)
        let repairedTodos = RichTextFormatting.normalizeTodoMarkers(in: rootView.textView)
        if repairedBullets || repairedTodos {
            self.note.text = rootView.textView.string
            self.note.richTextData = rootView.textView.textStorage.flatMap(RichTextCodec.encode)
            NoteStore.shared.update(self.note)
        }
        applyPinState()
        updateFormattingState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func close() {
        windowResidency.closeAll()
    }

    func showAndFocus() {
        note.isHidden = false
        NoteStore.shared.update(note)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(rootView.textView)
    }

    /// Shows the note without making it the key window, e.g. when it is restored while the
    /// 已完成的便签 list stays open.
    func showWithoutFocus() {
        windowResidency.activeWindow.orderFrontRegardless()
    }

    /// Brings the note onto the current desktop (Space) and back on screen.
    func gatherToCurrentDesktop() {
        guard let window else { return }
        note.isHidden = false
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }),
           let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        if note.isPinned {
            // Pinned notes already appear on every desktop.
            window.makeKeyAndOrderFront(nil)
        } else {
            let behavior = window.collectionBehavior
            window.collectionBehavior = behavior.union(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak window] in window?.collectionBehavior = behavior }
        }
        note.frame = WindowFrame(window.frame)
        NoteStore.shared.update(note)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    func windowDidResignKey(_ notification: Notification) {
        // Unpinned notes use the normal macOS window ordering. Losing keyboard
        // focus must not force the note behind every other window.
    }

    func textDidChange(_ notification: Notification) {
        if !isApplyingMarkdown {
            isApplyingMarkdown = true
            _ = RichTextFormatting.applyMarkdownSyntax(in: rootView.textView)
            isApplyingMarkdown = false
        }
        persistText()
        updateFormattingState()
        growToFitText()
        // A code block's background spans lines the edit itself did not touch.
        rootView.textView.needsDisplay = true
    }

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
        toCharacterRange newSelectedCharRange: NSRange
    ) -> NSRange {
        // Clicks and arrow keys, not typing, which also moves the selection.
        let event = NSApp.currentEvent
        let isArrowKey = event.map { $0.type == .keyDown && (123...126).contains($0.keyCode) } ?? false
        let isUserMove = isArrowKey || (event.map {
            [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains($0.type)
        } ?? false)
        let avoidingDividers = RichTextFormatting.selectionAvoidingDividers(
            newSelectedCharRange,
            from: oldSelectedCharRange,
            isUserMove: isUserMove,
            in: textView
        )
        return RichTextFormatting.selectionAvoidingListMarkers(
            avoidingDividers,
            from: oldSelectedCharRange,
            isUserMove: isUserMove,
            isKeyboard: isArrowKey,
            in: textView
        )
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        RichTextFormatting.leaveCodeStyleOnEmptyLastLine(in: rootView.textView)
        updateFormattingState()
    }

    func didChooseColor(_ color: NoteColor) {
        note.color = color
        rootView.updateColor(color)
        rootView.toolbar.update(color: color, isPinned: note.isPinned)
        NoteStore.shared.update(note)
    }

    func didTapArrange() { appController?.arrangeNotes() }

    func didBeginToolbarDrag(with event: NSEvent) {
        appController?.beginDragging(noteID: note.id, event: event)
    }

    func didTapBold() {
        let textView = rootView.textView
        RichTextFormatting.toggleBold(in: textView)
        textView.didChangeText()
        window?.makeFirstResponder(textView)
    }

    func didTapBulletList() {
        let textView = rootView.textView
        RichTextFormatting.toggleBulletList(in: textView)
        textView.didChangeText()
        window?.makeFirstResponder(textView)
    }

    func didTapOrderedList() {
        let textView = rootView.textView
        RichTextFormatting.toggleOrderedList(in: textView)
        textView.didChangeText()
        window?.makeFirstResponder(textView)
    }

    func didTapDivider() {
        let textView = rootView.textView
        window?.makeFirstResponder(textView)
        RichTextFormatting.insertDivider(in: textView)
    }

    func didTapCodeBlock() {
        let textView = rootView.textView
        window?.makeFirstResponder(textView)
        RichTextFormatting.toggleCodeBlock(in: textView)
        updateFormattingState()
    }

    func didTapTodo() {
        let textView = rootView.textView
        RichTextFormatting.toggleTodo(in: textView)
        textView.didChangeText()
        window?.makeFirstResponder(textView)
    }

    func didTapLink() {
        let textView = rootView.textView
        window?.makeFirstResponder(textView)
        NoteLinks.editLink(in: textView)
    }

    func didTapImage() {
        let textView = rootView.textView
        window?.makeFirstResponder(textView)
        NoteImages.chooseImages(into: textView)
    }

    func didTapNew() {
        guard let window else {
            appController?.createNote()
            return
        }
        let sourceFrame = window.frame
        let targetScreen = window.screen ?? NSScreen.screens.max { first, second in
            let firstIntersection = first.visibleFrame.intersection(sourceFrame)
            let secondIntersection = second.visibleFrame.intersection(sourceFrame)
            return firstIntersection.width * firstIntersection.height < secondIntersection.width * secondIntersection.height
        }
        guard let visibleFrame = targetScreen?.visibleFrame else {
            appController?.createNote()
            return
        }
        appController?.createNote(near: sourceFrame, in: visibleFrame)
    }

    func didTapPin() {
        setPinned(!note.isPinned, focus: !note.isPinned)
    }

    func setPinned(_ isPinned: Bool, focus: Bool) {
        guard note.isPinned != isPinned else { return }
        let wasPinned = note.isPinned
        note.isPinned = isPinned
        applyPinState(previouslyPinned: wasPinned, focusWhenPinned: focus)
        NoteStore.shared.update(note)
    }

    func didTapComplete() {
        let id = note.id
        window?.orderOut(nil)
        appController?.completeNote(id: id)
    }

    private func applyPinState(previouslyPinned: Bool? = nil, focusWhenPinned: Bool = false) {
        let isBecomingPinned = previouslyPinned == false && note.isPinned
        let isBecomingUnpinned = previouslyPinned == true && !note.isPinned

        if note.isPinned, windowResidency.pinnedWindow == nil {
            let proxyWindow = windowResidency.beginPinnedPresentation { [unowned self] in
                let window = StickyWindow(
                    contentRect: self.windowResidency.residentWindow.frame,
                    styleMask: [.borderless, .resizable, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                self.configureWindow(window)
                return window
            }
            self.window = proxyWindow
        } else if !note.isPinned, windowResidency.pinnedWindow != nil {
            self.window = windowResidency.endPinnedPresentation()
        }

        if let window {
            StickyWindowPresentation.apply(isPinned: note.isPinned, to: window)
        }
        rootView.toolbar.update(color: note.color, isPinned: note.isPinned)
        if isBecomingPinned {
            window?.orderFrontRegardless()
            if focusWhenPinned {
                window?.makeKey()
                window?.makeFirstResponder(rootView.textView)
            }
        } else if isBecomingUnpinned {
            window?.orderBack(nil)
        }
    }

    func move(to frame: NSRect) {
        guard let window else { return }
        window.minSize = NSSize(
            width: min(window.minSize.width, frame.width),
            height: min(window.minSize.height, frame.height)
        )
        window.setFrame(frame, display: true, animate: true)
        note.frame = WindowFrame(frame)
        NoteStore.shared.update(note)
    }

    func arrangeOnDesktop(to frame: NSRect) {
        guard let window else { return }
        let wasPinned = note.isPinned
        note.isPinned = false
        if wasPinned {
            applyPinState(previouslyPinned: true)
        } else {
            StickyWindowPresentation.apply(isPinned: false, to: window)
            rootView.toolbar.update(color: note.color, isPinned: false)
        }
        move(to: frame)
        self.window?.orderBack(nil)
    }

    func performWindowDrag(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    private func persistText() {
        note.text = rootView.textView.string
        if let storage = rootView.textView.textStorage {
            note.richTextData = RichTextCodec.encode(storage)
        }
        NoteStore.shared.update(note)
    }

    /// A click on a to-do circle checks or unchecks that item.
    private func toggleTodoMarker(at index: Int) {
        let textView = rootView.textView
        guard RichTextFormatting.toggleTodoCompletion(atParagraphStart: index, in: textView) else { return }
        window?.makeFirstResponder(textView)
        updateFormattingState()
    }

    private func updateFormattingState() {
        let textView = rootView.textView
        rootView.footer.updateFormatting(
            isBold: RichTextFormatting.isBold(in: textView),
            isBulletList: RichTextFormatting.isBulletList(in: textView),
            isOrderedList: RichTextFormatting.isOrderedList(in: textView),
            isTodoItem: RichTextFormatting.todoState(in: textView) != .plain,
            isCodeBlock: RichTextFormatting.isCodeBlock(in: textView)
        )
    }

    /// The window height that shows all of the text between the two bars, plus one empty
    /// line of room below it.
    private func heightFittingText() -> CGFloat? {
        let textView = rootView.textView
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
        layoutManager.ensureLayout(for: container)
        let textHeight = ceil(layoutManager.usedRect(for: container).height + 2 * textView.textContainerInset.height)
        let emptyLine = ceil(layoutManager.defaultLineHeight(for: NoteAppearance.bodyFont()) + NoteAppearance.paragraphSpacing)
        return textHeight + emptyLine + NoteAppearance.topBarHeight + NoteAppearance.bottomBarHeight
    }

    /// Extends the note downward while its text needs more room, keeping the top edge in place,
    /// until the bottom reaches the edge of the screen. It never shrinks the note.
    private func growToFitText() {
        guard let needed = heightFittingText(), needed > windowResidency.activeWindow.frame.height + 0.5 else { return }
        setHeight(needed, animate: false)
    }

    /// Double-clicking the bottom edge makes the note exactly as tall as its text, longer or
    /// shorter, keeping the top edge in place.
    func fitHeightToText() {
        guard let needed = heightFittingText() else { return }
        setHeight(max(needed, NoteAppearance.minimumSize.height), animate: true)
    }

    private func setHeight(_ requested: CGFloat, animate: Bool) {
        let window = windowResidency.activeWindow
        let frame = window.frame
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let height = min(requested, frame.maxY - visible.minY)
        guard abs(height - frame.height) > 0.5 else { return }
        let fitted = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        window.setFrame(fitted, display: true, animate: animate)
        saveFrame(fitted)
    }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        saveFrame(frame)
    }

    private func saveFrame(_ frame: NSRect) {
        note.frame = WindowFrame(frame)
        NoteStore.shared.update(note)
    }

    private func configureWindow(_ window: StickyWindow) {
        window.delegate = self
        window.onBottomEdgeDoubleClick = { [weak self] in self?.fitHeightToText() }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = NoteAppearance.minimumSize
        window.isMovableByWindowBackground = false
        window.animationBehavior = .utilityWindow
    }

}
