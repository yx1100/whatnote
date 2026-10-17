import AppKit

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
    /// Typed text always gets a note font. Without one AppKit falls back to its small default,
    /// which shows up as small Latin letters while input methods (Chinese) still look right.
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get { super.typingAttributes }
        set {
            var attributes = newValue
            attributes[.font] = NoteAppearance.noteFont(attributes[.font] as? NSFont)
            super.typingAttributes = attributes
        }
    }

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
    /// A locked note can be read, scrolled, selected and copied, but not changed or closed.
    var isLocked = false {
        didSet { isEditable = !isLocked }
    }

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
        if isLocked, modifiers.contains(.command) {
            if modifiers == [.command], key == "c" {
                copy(nil)
                return true
            }
            if modifiers == [.command], key == "a" {
                selectAll(nil)
                return true
            }
            // Formatting, cut, paste, links and ⌘W do nothing on a locked note.
            let blocked = modifiers == [.command] && ["b", "i", "7", "8", "9", "k", "w", "x", "v"].contains(key ?? "")
                || modifiers == [.command, .shift] && key == "u"
            return blocked || super.performKeyEquivalent(with: event)
        }
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
        guard modifiers.isEmpty, !hasMarkedText() else { return false }
        // A locked note is not closed by Esc.
        if isLocked { return true }
        guard ClosePreferences.closesOnDoubleEscape() else { return false }
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

    /// Copies list items as standard Markdown so other apps see checklists and bullets.
    /// Selections with images keep AppKit's rich copy.
    override func copy(_ sender: Any?) {
        guard let markdown = selectionAsMarkdown() else {
            super.copy(sender)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard selectionAsMarkdown() != nil else {
            super.cut(sender)
            return
        }
        copy(sender)
        insertText("", replacementRange: selectedRange())
    }

    private func selectionAsMarkdown() -> String? {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage, NSMaxRange(range) <= storage.length else { return nil }
        let selected = storage.attributedSubstring(from: range)
        var hasImage = false
        selected.enumerateAttribute(.attachment, in: NSRange(location: 0, length: selected.length)) { value, _, stop in
            if value != nil { hasImage = true; stop.pointee = true }
        }
        return hasImage ? nil : ListMarker.markdown(from: selected)
    }

    /// Dragging a selection leftward past a list item's text takes its whole marker at once,
    /// rather than first the gap between marker and text (as ⇧⌘← does from the keyboard).
    override func selectionRange(forProposedRange proposedCharRange: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        let range = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        let isMouse = NSApp?.currentEvent.map { [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains($0.type) } ?? false
        guard isMouse, range.length > 0, let storage = textStorage, range.location < storage.length else { return range }
        let string = storage.string as NSString
        let start = string.paragraphRange(for: NSRange(location: range.location, length: 0)).location
        guard range.location > start,
              let markerLength = ListMarker.length(in: string, atParagraphStart: start),
              range.location < start + markerLength else { return range }
        return NSRange(location: start, length: NSMaxRange(range) - start)
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
