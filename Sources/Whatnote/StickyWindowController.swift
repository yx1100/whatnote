import AppKit

@MainActor
final class StickyWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, StickyToolbarDelegate {
    private var note: StickyNote
    private let rootView: StickyRootView
    private let windowResidency: StickyWindowResidency
    private var isApplyingMarkdown = false
    weak var appController: AppController?
    var isPinned: Bool { note.isPinned }
    var isLocked: Bool { note.isLocked }
    var stickyWindows: [StickyWindow] { [windowResidency.residentWindow, windowResidency.pinnedWindow].compactMap { $0 } }

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
        let alignedLists = rootView.textView.textStorage.map(RichTextFormatting.alignListContinuationLines) ?? false
        if repairedBullets || repairedTodos || alignedLists {
            self.note.text = rootView.textView.string
            self.note.richTextData = rootView.textView.textStorage.flatMap(RichTextCodec.encode)
            NoteStore.shared.update(self.note)
        }
        applyPinState()
        applyLockState()
        updateFormattingState()
        // A note saved shorter than its text stays that size when edited.
        DispatchQueue.main.async { [weak self] in self?.updateGrowsWithText() }
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

    /// Dragging the note shorter than its text means the user wants it small; typing must not
    /// stretch it again. Making it tall enough for the text hands the sizing back.
    func windowDidEndLiveResize(_ notification: Notification) { updateGrowsWithText() }

    private func updateGrowsWithText() {
        guard let needed = heightFittingText() else { return }
        growsWithText = windowResidency.activeWindow.frame.height >= needed - 0.5
    }

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
        RichTextFormatting.alignListContinuationLines(in: rootView.textView.textStorage ?? NSTextStorage())
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
        RichTextFormatting.leaveHeadingStyleOnEmptyLine(in: rootView.textView)
        updateFormattingState()
    }

    func didChooseColor(_ color: NoteColor) {
        note.color = color
        rootView.updateColor(color)
        rootView.toolbar.update(color: color, isPinned: note.isPinned)
        NoteStore.shared.update(note)
    }

    func didTapArrange() { appController?.arrangeNotes() }

    /// Dragging from the lock button moves a locked note, which is otherwise fixed in place.
    func didBeginLockDrag(with event: NSEvent) {
        let window = windowResidency.activeWindow
        window.isMovable = true
        window.performDrag(with: event)
        window.isMovable = !note.isLocked
    }

    func didBeginToolbarDrag(with event: NSEvent) {
        guard !note.isLocked else { return }
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

    /// Locking takes the widget size from the top-left corner and remembers the old frame;
    /// unlocking puts the note back there.
    func didTapLock() {
        let window = windowResidency.activeWindow
        let frame = window.frame
        note.isLocked.toggle()
        var target: NSRect?
        if note.isLocked {
            note.unlockedFrame = WindowFrame(frame)
            let size = NoteAppearance.lockedSize
            target = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        } else if let before = note.unlockedFrame {
            note.unlockedFrame = nil
            target = before.rect
        }
        applyLockState()
        if let target {
            window.setFrame(target, display: true, animate: true)
            saveFrame(target)
        } else {
            NoteStore.shared.update(note)
        }
    }

    /// A locked note stays where it is and as it is: no dragging, resizing, editing or closing.
    /// It can still be scrolled, and its to-do items checked.
    private func applyLockState() {
        rootView.updateLock(note.isLocked)
        applyShadow()
        for window in [windowResidency.residentWindow, windowResidency.pinnedWindow].compactMap({ $0 }) {
            applyResizable(to: window)
        }
    }

    /// The flat locked note has no shadow. Only the window on show counts: the resident window
    /// behind a pinned note is invisible and stays without one.
    private func applyShadow() {
        windowResidency.activeWindow.hasShadow = !note.isLocked
    }

    private func applyResizable(to window: NSWindow) {
        window.isMovable = !note.isLocked
        if note.isLocked {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }
    }

    func didTapComplete() {
        guard !note.isLocked else { return }
        let id = note.id
        if let appController {
            appController.hideKeepingLockedNotesBehind { window?.orderOut(nil) }
        } else {
            window?.orderOut(nil)
        }
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
        applyShadow()
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

    /// Where the note is shown, including a pinned note's all-desktops window.
    var displayedFrame: NSRect { windowResidency.activeWindow.frame }

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
        // Checking an item is allowed on a locked note; only this edit gets through.
        let wasLocked = textView.isLocked
        if wasLocked { textView.isEditable = true }
        defer { if wasLocked { textView.isEditable = false } }
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
    /// False once the user has made the note shorter than its text.
    private var growsWithText = true

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
        guard growsWithText, !note.isLocked, let needed = heightFittingText(), needed > windowResidency.activeWindow.frame.height + 0.5 else { return }
        setHeight(needed, animate: false)
    }

    /// Double-clicking the bottom edge makes the note exactly as tall as its text, longer or
    /// shorter, keeping the top edge in place.
    func fitHeightToText() {
        guard !note.isLocked, let needed = heightFittingText() else { return }
        growsWithText = true
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
        applyResizable(to: window)
        window.animationBehavior = .utilityWindow
    }

}
