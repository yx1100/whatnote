import AppKit

@MainActor
enum RichTextFormatting {
    enum TodoState: Equatable {
        case plain
        case pending
        case completed
    }

    private static let listIndentStep: CGFloat = 18
    private static let maximumListLevel = 8
    private static let bulletMarkers = ["•", "∘", "▪"]
    private static let legacyBulletMarkers = ["◦", "○"]
    private static let pendingTodoMarker = "☐"
    private static let completedTodoMarker = "☑"

    static func toggleBold(in textView: NSTextView) {
        toggleFontTrait(.boldFontMask, in: textView)
    }

    static func toggleItalic(in textView: NSTextView) {
        toggleFontTrait(.italicFontMask, in: textView)
    }

    static func isItalic(in textView: NSTextView) -> Bool {
        NSFontManager.shared.traits(of: font(in: textView)).contains(.italicFontMask)
    }

    private static func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
        let storage = textView.textStorage ?? NSTextStorage()
        let selected = textView.selectedRange()
        let currentFont = font(in: textView)
        let shouldAdd = !NSFontManager.shared.traits(of: currentFont).contains(trait)

        if selected.length > 0 {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: selected) { value, range, _ in
                let source = (value as? NSFont) ?? NoteAppearance.bodyFont()
                let converted = shouldAdd
                    ? NSFontManager.shared.convert(source, toHaveTrait: trait)
                    : NSFontManager.shared.convert(source, toNotHaveTrait: trait)
                storage.addAttribute(.font, value: converted, range: range)
            }
            storage.endEditing()
        } else {
            var typing = textView.typingAttributes
            typing[.font] = shouldAdd
                ? NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
                : NSFontManager.shared.convert(currentFont, toNotHaveTrait: trait)
            textView.typingAttributes = typing
        }
    }

    /// Mark as Checked (⇧⌘U): checks the selected checklist items, or unchecks them
    /// when all are already checked.
    static func toggleCheckedState(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let starts = paragraphStarts(in: storage.string, selection: textView.selectedRange())
            .filter { todoState(in: storage.string, at: $0) != .plain }
        guard !starts.isEmpty else { return }
        let check = starts.contains { todoState(in: storage.string, at: $0) == .pending }
        for start in starts where (todoState(in: storage.string, at: start) == .pending) == check {
            toggleTodoCompletion(atParagraphStart: start, in: textView)
        }
    }

    /// The to-do button: turns lines into to-do items, or back into plain lines when
    /// every selected line already is one. Checking an item is done by clicking its circle.
    static func toggleTodo(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selected = textView.selectedRange()
        let starts = paragraphStarts(in: storage.string, selection: selected)
        let allTodos = !starts.isEmpty && starts.allSatisfy { todoState(in: storage.string, at: $0) != .plain }
        var newLocation = selected.location
        var newLength = selected.length

        storage.beginEditing()
        for start in starts.reversed() {
            if allTodos {
                storage.replaceCharacters(in: NSRange(location: start, length: 2), with: "")
                adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: -2)
                applyTodoCompletion(false, storage: storage, paragraphStart: min(start, storage.length))
            } else if todoState(in: storage.string, at: start) == .plain {
                if let ordered = orderedMarker(in: storage.string, at: start) {
                    storage.replaceCharacters(in: NSRange(location: start, length: ordered.length), with: "")
                    adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: -ordered.length)
                }
                if hasBullet(in: storage.string, at: start) {
                    storage.replaceCharacters(in: NSRange(location: start, length: 1), with: pendingTodoMarker)
                    applyListIndent(false, storage: storage, location: start)
                } else {
                    insertMarker("\(pendingTodoMarker) ", at: start, storage: storage, textView: textView)
                    adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: 2)
                }
                applyTodoCompletion(false, storage: storage, paragraphStart: start)
            }
        }
        storage.endEditing()

        let selection = NSRange(
            location: min(newLocation, storage.length),
            length: min(newLength, max(0, storage.length - newLocation))
        )
        textView.setSelectedRange(selection)
        setTypingListIndent(false, textView: textView)
        setTypingTodoCompletion(false, textView: textView)
    }

    /// Inserts a list or to-do marker with the line's own font. A plain string inserted
    /// into an empty note would get AppKit's small default font, and later typing inherits it.
    private static func insertMarker(_ marker: String, at location: Int, storage: NSTextStorage, textView: NSTextView) {
        var attributes = storage.length > 0
            ? storage.attributes(at: min(location, storage.length - 1), effectiveRange: nil)
            : textView.typingAttributes
        if storage.length > 0, (storage.string as NSString).character(at: min(location, storage.length - 1)) == 0x0A {
            // An empty line only holds its newline; what the user is about to type matters more.
            attributes = textView.typingAttributes
        }
        attributes.removeValue(forKey: .strikethroughStyle)
        attributes.removeValue(forKey: .link)
        attributes.removeValue(forKey: .attachment)
        // A list item is body text, even on an empty line that still carries a heading's font.
        if attributes[.font] == nil || headingLevel(of: attributes[.font] as? NSFont) != nil {
            attributes[.font] = NoteAppearance.bodyFont()
            var typing = textView.typingAttributes
            typing[.font] = NoteAppearance.bodyFont()
            textView.typingAttributes = typing
        }
        storage.replaceCharacters(in: NSRange(location: location, length: 0), with: NSAttributedString(string: marker, attributes: attributes))
    }

    /// Checks or unchecks the to-do item whose marker is at `start`; used by clicks on the checkbox.
    /// Unlike `toggleTodo`, it never turns the line back into plain text.
    @discardableResult
    static func toggleTodoCompletion(atParagraphStart start: Int, in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let state = todoState(in: storage.string, at: start)
        guard state != .plain else { return false }
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: start, length: 0))
        // Registering the whole paragraph lets undo restore both the marker and the strikethrough.
        guard textView.shouldChangeText(in: paragraph, replacementString: nil) else { return false }
        // Ticking a box should not move the cursor; the edit keeps the text length.
        let savedSelection = textView.selectedRanges
        let completed = state == .pending
        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: start, length: 1),
            with: completed ? completedTodoMarker : pendingTodoMarker
        )
        applyTodoCompletion(completed, storage: storage, paragraphStart: start)
        storage.endEditing()
        textView.selectedRanges = savedSelection
        textView.didChangeText()
        return true
    }

    static func toggleBulletList(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selected = textView.selectedRange()
        let starts = paragraphStarts(in: storage.string, selection: selected)
        let allBulleted = !starts.isEmpty && starts.allSatisfy { hasBullet(in: storage.string, at: $0) }
        var newLocation = selected.location
        var newLength = selected.length

        storage.beginEditing()
        for start in starts.reversed() {
            if allBulleted, hasBullet(in: storage.string, at: start) {
                storage.replaceCharacters(in: NSRange(location: start, length: 2), with: "")
                adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: -2)
                applyListIndent(false, storage: storage, location: min(start, storage.length))
            } else if !allBulleted, !hasBullet(in: storage.string, at: start) {
                if let ordered = orderedMarker(in: storage.string, at: start) {
                    storage.replaceCharacters(in: NSRange(location: start, length: ordered.length), with: "")
                    adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: -ordered.length)
                }
                if todoState(in: storage.string, at: start) == .plain {
                    insertMarker("• ", at: start, storage: storage, textView: textView)
                    adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: 2)
                } else {
                    storage.replaceCharacters(in: NSRange(location: start, length: 1), with: "•")
                    applyTodoCompletion(false, storage: storage, paragraphStart: start)
                }
                applyListIndent(true, storage: storage, location: start)
            }
        }
        storage.endEditing()
        setTypingListIndent(!allBulleted, textView: textView)
        if !allBulleted { setTypingTodoCompletion(false, textView: textView) }
        textView.setSelectedRange(NSRange(location: min(newLocation, storage.length), length: min(newLength, max(0, storage.length - newLocation))))
    }

    @discardableResult
    static func adjustBulletLevel(in textView: NSTextView, delta: Int) -> Bool {
        guard delta == -1 || delta == 1, let storage = textView.textStorage else { return false }
        let originalSelection = textView.selectedRange()
        let starts = paragraphStarts(in: storage.string, selection: originalSelection)
            .filter { hasBullet(in: storage.string, at: $0) }
        guard !starts.isEmpty else { return false }

        var changed = false
        storage.beginEditing()
        for start in starts {
            guard start < storage.length else { continue }
            let paragraphRange = (storage.string as NSString).paragraphRange(for: NSRange(location: start, length: 0))
            let existing = storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle
            let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            let currentLevel = max(0, Int(round(style.firstLineHeadIndent / listIndentStep)))
            let requestedLevel = min(maximumListLevel, max(0, currentLevel + delta))
            let newLevel: Int
            if delta > 0 {
                let parentLimit = previousBulletLevel(before: start, storage: storage).map { $0 + 1 } ?? 0
                newLevel = min(requestedLevel, parentLimit)
            } else {
                newLevel = requestedLevel
            }
            guard newLevel != currentLevel else { continue }
            storage.replaceCharacters(
                in: NSRange(location: start, length: 1),
                with: bulletMarker(for: newLevel)
            )
            style.firstLineHeadIndent = CGFloat(newLevel) * listIndentStep
            style.headIndent = CGFloat(newLevel + 1) * listIndentStep
            storage.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            changed = true
        }
        storage.endEditing()

        if changed {
            let selection = NSRange(
                location: min(originalSelection.location, storage.length),
                length: min(originalSelection.length, max(0, storage.length - originalSelection.location))
            )
            textView.setSelectedRange(selection)
            let location = storage.length == 0 ? 0 : min(selection.location, storage.length - 1)
            let style = storage.length == 0 ? nil : storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            setTypingListLevel(max(0, Int(round((style?.firstLineHeadIndent ?? 0) / listIndentStep))), textView: textView)
        }
        return changed
    }

    /// Backspace right after a to-do or list marker removes the whole marker, turning
    /// the line into plain text. Deleting only the space would leave a bare "☐" glyph.
    static func handleMarkerBackspace(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location >= 2 else { return false }
        let nsString = storage.string as NSString
        let start = nsString.paragraphRange(for: NSRange(location: selection.location - 1, length: 0)).location
        let markerLength: Int
        if todoState(in: storage.string, at: start) != .plain || hasBullet(in: storage.string, at: start) {
            markerLength = 2
        } else if let ordered = orderedMarker(in: storage.string, at: start) {
            markerLength = ordered.length
        } else {
            return false
        }
        guard start + markerLength == selection.location else { return false }
        let markerRange = NSRange(location: start, length: markerLength)
        guard textView.shouldChangeText(in: markerRange, replacementString: "") else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: markerRange, with: "")
        applyTodoCompletion(false, storage: storage, paragraphStart: start)
        applyListIndent(false, storage: storage, location: start)
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: start, length: 0))
        setTypingListIndent(false, textView: textView)
        setTypingTodoCompletion(false, textView: textView)
        textView.didChangeText()
        return true
    }

    /// Repairs to-do markers that lost the space after them, which older versions allowed.
    @discardableResult
    static func normalizeTodoMarkers(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let starts = paragraphStarts(in: storage.string, selection: NSRange(location: 0, length: storage.length))
        var changed = false
        storage.beginEditing()
        for start in starts.reversed() where start < storage.length {
            let nsString = storage.string as NSString
            let marker = nsString.substring(with: NSRange(location: start, length: 1))
            guard marker == pendingTodoMarker || marker == completedTodoMarker,
                  todoState(in: storage.string, at: start) == .plain else { continue }
            let attributes = storage.attributes(at: start, effectiveRange: nil)
            storage.insert(NSAttributedString(string: " ", attributes: attributes), at: start + 1)
            changed = true
        }
        storage.endEditing()
        return changed
    }

    @discardableResult
    static func normalizeBulletMarkers(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let starts = paragraphStarts(
            in: storage.string,
            selection: NSRange(location: 0, length: storage.length)
        ).filter { hasBullet(in: storage.string, at: $0) }
        var changed = false
        storage.beginEditing()
        for start in starts {
            let style = storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle
            let level = max(0, Int(round((style?.firstLineHeadIndent ?? 0) / listIndentStep)))
            let expected = bulletMarker(for: level)
            guard bulletMarker(in: storage.string, at: start) != expected else { continue }
            storage.replaceCharacters(in: NSRange(location: start, length: 1), with: expected)
            changed = true
        }
        storage.endEditing()
        return changed
    }

    private static func previousBulletLevel(before start: Int, storage: NSTextStorage) -> Int? {
        guard start > 0, storage.length > 0 else { return nil }
        let previousRange = (storage.string as NSString).paragraphRange(for: NSRange(location: start - 1, length: 0))
        guard hasBullet(in: storage.string, at: previousRange.location) else { return nil }
        let style = storage.attribute(.paragraphStyle, at: previousRange.location, effectiveRange: nil) as? NSParagraphStyle
        return max(0, Int(round((style?.firstLineHeadIndent ?? 0) / listIndentStep)))
    }

    static func isBold(in textView: NSTextView) -> Bool {
        NSFontManager.shared.traits(of: font(in: textView)).contains(.boldFontMask)
    }

    static func todoState(in textView: NSTextView) -> TodoState {
        guard let storage = textView.textStorage else { return .plain }
        let start = paragraphStarts(in: storage.string, selection: textView.selectedRange()).first ?? 0
        return todoState(in: storage.string, at: start)
    }

    /// The numbered-list button: numbers the selected lines, continuing a list right above
    /// them, or removes the numbers when every selected line already has one.
    static func toggleOrderedList(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selected = textView.selectedRange()
        let starts = paragraphStarts(in: storage.string, selection: selected)
        let allOrdered = !starts.isEmpty && starts.allSatisfy { orderedMarker(in: storage.string, at: $0) != nil }
        var firstNumber = 1
        if let first = starts.first, first > 0 {
            let previous = (storage.string as NSString).paragraphRange(for: NSRange(location: first - 1, length: 0))
            if let marker = orderedMarker(in: storage.string, at: previous.location) {
                firstNumber = marker.number + 1
            }
        }
        var newLocation = selected.location
        var newLength = selected.length

        storage.beginEditing()
        for (index, start) in starts.enumerated().reversed() {
            if let ordered = orderedMarker(in: storage.string, at: start) {
                storage.replaceCharacters(in: NSRange(location: start, length: ordered.length), with: "")
                adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: -ordered.length)
            } else if hasBullet(in: storage.string, at: start) {
                storage.replaceCharacters(in: NSRange(location: start, length: 2), with: "")
                adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: -2)
                applyListIndent(false, storage: storage, location: min(start, storage.length))
            } else if todoState(in: storage.string, at: start) != .plain {
                storage.replaceCharacters(in: NSRange(location: start, length: 2), with: "")
                adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: -2)
                applyTodoCompletion(false, storage: storage, paragraphStart: min(start, storage.length))
            }
            guard !allOrdered else { continue }
            let marker = "\(firstNumber + index). "
            insertMarker(marker, at: start, storage: storage, textView: textView)
            adjustSelection(location: &newLocation, length: &newLength, changeAt: start, delta: (marker as NSString).length)
        }
        storage.endEditing()

        textView.setSelectedRange(NSRange(
            location: min(newLocation, storage.length),
            length: min(newLength, max(0, storage.length - newLocation))
        ))
        setTypingListIndent(false, textView: textView)
        setTypingTodoCompletion(false, textView: textView)
    }

    /// A divider is "---" drawn as a line, so the cursor may only sit at its left end; a click or
    /// arrow key that lands among the dashes moves there instead. Pressing → at the left end
    /// moves on to the next line. `isUserMove` is false while typing, so "---" can be typed.
    static func selectionAvoidingDividers(
        _ proposed: NSRange,
        from old: NSRange,
        isUserMove: Bool,
        in textView: NSTextView
    ) -> NSRange {
        guard isUserMove, proposed.length == 0, let storage = textView.textStorage,
              proposed.location < storage.length,
              let divider = dividerParagraph(containing: proposed.location, in: storage),
              proposed.location > divider.location else { return proposed }
        let hasNewline = (storage.string as NSString).character(at: NSMaxRange(divider) - 1) == 0x0A
        if old.length == 0, old.location == divider.location, proposed.location > old.location, hasNewline {
            return NSRange(location: NSMaxRange(divider), length: 0)
        }
        return NSRange(location: divider.location, length: 0)
    }

    /// The cursor never stops inside a list or to-do marker such as "☐ ", "• " or "1. ": it goes
    /// to the start of the item's text. Moving left from there goes on to the line above.
    /// A selection dragged into a marker takes the whole marker, so one Delete clears the line.
    /// With the keyboard (⇧⌘←, ⇧←) the selection first stops at the start of the text and takes
    /// the marker on the next press.
    static func selectionAvoidingListMarkers(
        _ proposed: NSRange,
        from old: NSRange,
        isUserMove: Bool,
        isKeyboard: Bool = false,
        in textView: NSTextView
    ) -> NSRange {
        guard isUserMove, let storage = textView.textStorage, storage.length > 0 else { return proposed }
        let string = storage.string as NSString
        let lookup = min(proposed.location, string.length - 1)
        if proposed.location >= string.length, string.character(at: string.length - 1) == 0x0A { return proposed }
        let paragraph = string.paragraphRange(for: NSRange(location: lookup, length: 0))
        let start = paragraph.location
        guard !CodeBlock.isCodeLine(in: storage, at: start),
              let length = ListMarker.length(in: string, atParagraphStart: start),
              proposed.location < start + length else { return proposed }
        let textStart = start + length
        if proposed.length > 0 {
            let end = NSMaxRange(proposed)
            // From the keyboard, a selection not yet at the start of the text stops there first.
            if isKeyboard, old.location != textStart, end > textStart {
                return NSRange(location: textStart, length: end - textStart)
            }
            return NSRange(location: start, length: end - start)
        }
        if old.length == 0, old.location == textStart, proposed.location < old.location, start > 0 {
            return NSRange(location: start - 1, length: 0)
        }
        return NSRange(location: textStart, length: 0)
    }

    /// Plain text about to be pasted. A marker only means something at the start of a line, so
    /// it is dropped from the start of the pasted text when the cursor is after other text or
    /// already after a marker; it would otherwise show up as a stray "☐".
    static func textForPaste(_ text: String, in textView: NSTextView) -> String {
        guard let storage = textView.textStorage, storage.length > 0 else { return text }
        let string = storage.string as NSString
        let location = textView.selectedRange().location
        if location >= string.length, string.character(at: string.length - 1) == 0x0A { return text }
        let start = string.paragraphRange(for: NSRange(location: min(location, string.length - 1), length: 0)).location
        let pasted = text as NSString
        guard location > start, let markerLength = ListMarker.length(in: pasted, atParagraphStart: 0) else { return text }
        let pastesTodo = TodoMarker.isCompleted(in: pasted, at: 0) != nil
        let afterMarker = ListMarker.length(in: string, atParagraphStart: start).map { start + $0 == location } ?? false
        guard pastesTodo || afterMarker else { return text }
        return pasted.substring(from: markerLength)
    }

    /// Backspace at the start of the line below a divider deletes the divider's last dash
    /// rather than the hidden line break, and moves the cursor to where that dash was.
    /// At a divider's left end Backspace works as usual and joins it to the line above.
    static func handleDividerBackspace(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location > 1 else { return false }
        let string = storage.string as NSString
        guard string.character(at: selection.location - 1) == 0x0A,
              dividerParagraph(containing: selection.location - 1, in: storage) != nil else { return false }
        let lastDash = NSRange(location: selection.location - 2, length: 1)
        guard textView.shouldChangeText(in: lastDash, replacementString: "") else { return true }
        storage.replaceCharacters(in: lastDash, with: "")
        textView.setSelectedRange(NSRange(location: lastDash.location, length: 0))
        textView.didChangeText()
        return true
    }

    /// The whole paragraph (with its line break) when the one at `location` is a divider.
    private static func dividerParagraph(containing location: Int, in storage: NSTextStorage) -> NSRange? {
        let string = storage.string as NSString
        guard location >= 0, location < string.length,
              !CodeBlock.isCodeLine(in: storage, at: location) else { return nil }
        let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
        var content = paragraph
        while content.length > 0, [0x0A, 0x0D, 0x2029].contains(string.character(at: NSMaxRange(content) - 1)) {
            content.length -= 1
        }
        return DividerLine.isDivider(string.substring(with: content)) ? paragraph : nil
    }

    /// Puts a "---" divider on its own line at the cursor and moves the cursor below it.
    static func insertDivider(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let nsString = storage.string as NSString
        let startsLine = selection.location == 0 || nsString.character(at: selection.location - 1) == 0x0A
        let text = (startsLine ? "" : "\n") + "\(DividerLine.marker)\n"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NoteAppearance.bodyFont(),
            .foregroundColor: NoteAppearance.textColor
        ]
        guard textView.shouldChangeText(in: selection, replacementString: text) else { return }
        storage.replaceCharacters(in: selection, with: NSAttributedString(string: text, attributes: attributes))
        textView.setSelectedRange(NSRange(location: selection.location + (text as NSString).length, length: 0))
        textView.typingAttributes = attributes
        textView.didChangeText()
    }

    static func isOrderedList(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        return paragraphStarts(in: storage.string, selection: textView.selectedRange()).first.map {
            orderedMarker(in: storage.string, at: $0) != nil
        } ?? false
    }

    private static let orderedMarkerExpression = try? NSRegularExpression(pattern: #"(\d{1,4})\. "#)

    /// A numbered-list marker such as "12. " starting at `location`.
    private static func orderedMarker(in string: String, at location: Int) -> (number: Int, length: Int)? {
        let nsString = string as NSString
        guard location < nsString.length,
              let expression = orderedMarkerExpression,
              let match = expression.firstMatch(
                  in: string,
                  options: .anchored,
                  range: NSRange(location: location, length: nsString.length - location)
              ),
              let number = Int(nsString.substring(with: match.range(at: 1))) else { return nil }
        return (number, match.range.length)
    }

    /// Keeps the numbered items after `paragraphStart` counting up from its number.
    private static func renumberOrderedList(after paragraphStart: Int, in textView: NSTextView) {
        guard let storage = textView.textStorage,
              var expected = orderedMarker(in: storage.string, at: paragraphStart)?.number else { return }
        var cursor = NSMaxRange((storage.string as NSString).paragraphRange(for: NSRange(location: paragraphStart, length: 0)))
        while cursor < storage.length, let marker = orderedMarker(in: storage.string, at: cursor) {
            expected += 1
            let paragraphEnd = NSMaxRange((storage.string as NSString).paragraphRange(for: NSRange(location: cursor, length: 0)))
            guard marker.number != expected else {
                cursor = paragraphEnd
                continue
            }
            let replacement = "\(expected). "
            let range = NSRange(location: cursor, length: marker.length)
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            storage.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            cursor = paragraphEnd + (replacement as NSString).length - marker.length
        }
    }

    static func isBulletList(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        return paragraphStarts(in: storage.string, selection: textView.selectedRange()).first.map {
            hasBullet(in: storage.string, at: $0)
        } ?? false
    }

    private static let headingSizes: [CGFloat] = [22, 19, 17]
    private static let codeBackground = NSColor.black.withAlphaComponent(0.07)

    static func headingFont(level: Int) -> NSFont {
        let clamped = min(max(level, 1), headingSizes.count)
        return NSFont.systemFont(ofSize: headingSizes[clamped - 1], weight: clamped == 3 ? .semibold : .bold)
    }

    static func headingLevel(of font: NSFont?) -> Int? {
        guard let font else { return nil }
        return headingSizes.firstIndex(where: { abs($0 - font.pointSize) < 0.5 }).map { $0 + 1 }
    }

    static func codeFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: NoteAppearance.bodyFontSize - 1, weight: .regular)
    }

    /// Converts Markdown syntax into rich text as it is typed or pasted:
    /// `# 标题`, `**粗体**`, `*斜体*`, `~~删除线~~`, `` `代码` ``, ```` ``` ```` 代码块, `[文字](网址)`, `- 列表`, `- [ ] 待办`.
    @discardableResult
    static func applyMarkdownSyntax(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, !textView.hasMarkedText() else { return false }
        var selection = textView.selectedRange()
        let originalTypingAttributes = textView.typingAttributes
        var headingTypingFont: NSFont?
        var changed = false

        // Markdown inside code blocks stays as typed.
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
            return expression.matches(in: storage.string, range: NSRange(location: 0, length: storage.length))
                .filter { !CodeBlock.isCodeLine(in: storage, at: $0.range.location) }
        }

        func replace(_ range: NSRange, with replacement: NSAttributedString) {
            storage.replaceCharacters(in: range, with: replacement)
            selection = adjustedSelection(selection, replacing: range, newLength: replacement.length)
            changed = true
        }

        func inner(_ match: NSTextCheckingResult, group: Int = 1) -> NSMutableAttributedString {
            NSMutableAttributedString(attributedString: storage.attributedSubstring(from: match.range(at: group)))
        }

        func convertFonts(in value: NSMutableAttributedString, _ transform: @escaping (NSFont) -> NSFont) {
            value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { font, range, _ in
                value.addAttribute(.font, value: transform((font as? NSFont) ?? NoteAppearance.bodyFont()), range: range)
            }
        }

        // ```
        // 代码
        // ```  — usually pasted; typing a fence and Return starts a block right away.
        for match in matches(#"(?m)^[ \t]*```[^`\s]*[ \t]*\n((?:.*\n)+?)[ \t]*```[ \t]*$"#).reversed() {
            var code = (storage.string as NSString).substring(with: match.range(at: 1))
            if NSMaxRange(match.range) < storage.length { code.removeLast() }
            let start = match.range.location
            replace(match.range, with: NSAttributedString(string: code, attributes: CodeBlock.attributes()))
            let paragraphs = (storage.string as NSString).paragraphRange(
                for: NSRange(location: start, length: max(0, (code as NSString).length - 1))
            )
            storage.addAttribute(.paragraphStyle, value: CodeBlock.paragraphStyle(), range: paragraphs)
        }

        // [文字](网址) — image syntax `![...](...)` is left alone.
        for match in matches(#"(?<!!)\[([^\]\n]+)\]\(([^)\s]+)\)"#).reversed() {
            let address = (storage.string as NSString).substring(with: match.range(at: 2))
            guard let url = NoteLinks.url(from: address) else { continue }
            let replacement = inner(match)
            replacement.addAttribute(.link, value: url, range: NSRange(location: 0, length: replacement.length))
            replace(match.range, with: replacement)
        }

        // `代码`
        for match in matches(#"`([^`\n]+)`"#).reversed() {
            let replacement = inner(match)
            let whole = NSRange(location: 0, length: replacement.length)
            replacement.addAttribute(.font, value: codeFont(), range: whole)
            replacement.addAttribute(.backgroundColor, value: codeBackground, range: whole)
            replace(match.range, with: replacement)
        }

        // **粗体**
        for match in matches(#"\*\*([^*\n]+)\*\*"#).reversed() {
            let replacement = inner(match)
            convertFonts(in: replacement) { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) }
            replace(match.range, with: replacement)
        }

        // *斜体* — not inside words like 2*3*4, and never a list marker.
        for match in matches(#"(?<![*A-Za-z0-9\\])\*(?![\s*])([^*\n]*?[^\s*])\*(?![*A-Za-z0-9])"#).reversed() {
            let replacement = inner(match)
            convertFonts(in: replacement) { NSFontManager.shared.convert($0, toHaveTrait: .italicFontMask) }
            replace(match.range, with: replacement)
        }

        // ~~删除线~~
        for match in matches(#"~~([^~\n]+)~~"#).reversed() {
            let replacement = inner(match)
            replacement.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: NSRange(location: 0, length: replacement.length)
            )
            replace(match.range, with: replacement)
        }

        // # 标题 / ## 标题 / ### 标题
        for match in matches(#"(?m)^(#{1,3}) "#).reversed() {
            let font = headingFont(level: match.range(at: 1).length)
            let start = match.range.location
            replace(match.range, with: NSAttributedString())
            let paragraph = start < storage.length
                ? (storage.string as NSString).paragraphRange(for: NSRange(location: start, length: 0))
                : NSRange(location: start, length: 0)
            if paragraph.length > 0 {
                storage.addAttribute(.font, value: font, range: paragraph)
            }
            var contentEnd = NSMaxRange(paragraph)
            if contentEnd > paragraph.location,
               (storage.string as NSString).substring(with: NSRange(location: contentEnd - 1, length: 1)) == "\n" {
                contentEnd -= 1
            }
            if selection.location >= paragraph.location, selection.location <= contentEnd {
                headingTypingFont = font
            }
        }

        // - [ ] 待办 / - [x] 已完成 (also after "- " has already become "• ")
        for match in matches(#"(?m)^[*\-•] \[( |x|X)\] "#).reversed() {
            let start = match.range.location
            let isDone = (storage.string as NSString).substring(with: match.range(at: 1)) != " "
            var attributes = storage.attributes(at: start, effectiveRange: nil)
            attributes.removeValue(forKey: .strikethroughStyle)
            replace(match.range, with: NSAttributedString(
                string: "\(isDone ? completedTodoMarker : pendingTodoMarker) ",
                attributes: attributes
            ))
            applyListIndent(false, storage: storage, location: start)
            applyTodoCompletion(isDone, storage: storage, paragraphStart: start)
        }

        // - 列表 / * 列表
        for match in matches(#"(?m)^[*-] "#).reversed() {
            storage.replaceCharacters(in: match.range, with: "• ")
            applyListIndent(true, storage: storage, location: match.range.location)
            changed = true
        }

        if changed {
            textView.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: min(selection.length, max(0, storage.length - selection.location))))
            textView.typingAttributes = originalTypingAttributes
            setTypingListIndent(isBulletList(in: textView), textView: textView)
            if let headingTypingFont {
                var typing = textView.typingAttributes
                typing[.font] = headingTypingFont
                textView.typingAttributes = typing
            }
        }
        return changed
    }

    static func handleStructuredNewline(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location <= storage.length else { return false }
        let nsString = storage.string as NSString
        // On the empty last line the cursor sits after the final line break; that line is
        // plain, not part of the item above it.
        let atEmptyLastLine = selection.location == storage.length
            && (storage.length == 0 || nsString.character(at: storage.length - 1) == 0x0A)
        let paragraph = atEmptyLastLine
            ? NSRange(location: storage.length, length: 0)
            : nsString.paragraphRange(for: NSRange(location: min(selection.location, storage.length - 1), length: 0))

        if let handled = handleCodeNewline(in: textView, selection: selection) { return handled }

        let taskState = todoState(in: storage.string, at: paragraph.location)
        if taskState != .plain {
            setTypingTodoCompletion(false, textView: textView)
            if isEmptyItem(paragraph, markerLength: 2, in: nsString) {
                storage.replaceCharacters(in: NSRange(location: paragraph.location, length: 2), with: "")
                textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
                textView.didChangeText()
            } else {
                let insertion = NSAttributedString(
                    string: "\n\(pendingTodoMarker) ",
                    attributes: textView.typingAttributes
                )
                storage.beginEditing()
                storage.replaceCharacters(in: selection, with: insertion)
                applyTodoCompletion(false, storage: storage, paragraphStart: selection.location + 1)
                storage.endEditing()
                textView.setSelectedRange(NSRange(location: selection.location + insertion.length, length: 0))
                textView.didChangeText()
            }
            return true
        }

        if let ordered = orderedMarker(in: storage.string, at: paragraph.location) {
            if isEmptyItem(paragraph, markerLength: ordered.length, in: nsString) {
                // Return on an empty numbered item ends the list.
                let markerRange = NSRange(location: paragraph.location, length: ordered.length)
                guard textView.shouldChangeText(in: markerRange, replacementString: "") else { return true }
                storage.replaceCharacters(in: markerRange, with: "")
                textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
                textView.didChangeText()
            } else {
                textView.insertText("\n\(ordered.number + 1). ", replacementRange: selection)
                renumberOrderedList(after: selection.location + 1, in: textView)
            }
            return true
        }

        guard let marker = bulletMarker(in: storage.string, at: paragraph.location) else {
            return endHeadingOnNewline(in: textView, selection: selection)
        }

        if isEmptyItem(paragraph, markerLength: 2, in: nsString) {
            storage.replaceCharacters(in: NSRange(location: paragraph.location, length: 2), with: "")
            setTypingListIndent(false, textView: textView)
            textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
            textView.didChangeText()
        } else {
            textView.insertText("\n\(marker) ", replacementRange: selection)
        }
        return true
    }

    /// The code block button: turns the selected lines into a code block, or back into
    /// plain text when they all are code already.
    static func toggleCodeBlock(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let nsString = storage.string as NSString
        let atEmptyLastLine = selection.location >= storage.length
            && (storage.length == 0 || nsString.character(at: storage.length - 1) == 0x0A)
        if atEmptyLastLine {
            // Give the new block a real line so it has something to draw.
            let end = NSRange(location: storage.length, length: 0)
            let attributes = CodeBlock.attributes()
            guard textView.shouldChangeText(in: end, replacementString: "\n") else { return }
            storage.replaceCharacters(in: end, with: NSAttributedString(string: "\n", attributes: attributes))
            textView.setSelectedRange(end)
            textView.typingAttributes = attributes
            textView.didChangeText()
            textView.needsDisplay = true
            return
        }

        let location = min(selection.location, storage.length - 1)
        let paragraphs = nsString.paragraphRange(
            for: NSRange(location: location, length: min(selection.length, storage.length - location))
        )
        let makeCode = !paragraphStarts(in: storage.string, selection: paragraphs)
            .allSatisfy { CodeBlock.isCodeLine(in: storage, at: $0) }
        let attributes = makeCode ? CodeBlock.attributes() : CodeBlock.bodyAttributes()
        guard textView.shouldChangeText(in: paragraphs, replacementString: nil) else { return }
        let savedSelection = textView.selectedRanges
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: paragraphs)
        storage.addAttributes(attributes, range: paragraphs)
        storage.endEditing()
        textView.selectedRanges = savedSelection
        textView.typingAttributes = attributes
        textView.didChangeText()
        textView.needsDisplay = true
    }

    static func isCodeBlock(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, !isAtEmptyLastLine(textView) else { return false }
        return CodeBlock.isCodeLine(in: storage, at: min(textView.selectedRange().location, storage.length - 1))
    }

    /// Code lines always end with their own newline, so the empty line after a block at the
    /// end of the note is plain text. Clicking there must not keep typing in code style.
    /// An empty line starts in body text even right below a heading, whose font AppKit would
    /// otherwise carry over; two headings in a row are rare.
    static func leaveHeadingStyleOnEmptyLine(in textView: NSTextView) {
        guard let storage = textView.textStorage,
              headingLevel(of: textView.typingAttributes[.font] as? NSFont) != nil else { return }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return }
        let string = storage.string as NSString
        let atEnd = selection.location >= string.length
        let onEmptyLine = atEnd
            ? (string.length == 0 || string.character(at: string.length - 1) == 0x0A)
            : string.character(at: selection.location) == 0x0A
                && (selection.location == 0 || string.character(at: selection.location - 1) == 0x0A)
        guard onEmptyLine else { return }
        // The line's own break sets its height, and so the cursor's.
        if !atEnd {
            storage.addAttribute(.font, value: NoteAppearance.bodyFont(), range: NSRange(location: selection.location, length: 1))
        }
        var typing = textView.typingAttributes
        typing[.font] = NoteAppearance.bodyFont()
        textView.typingAttributes = typing
    }

    static func leaveCodeStyleOnEmptyLastLine(in textView: NSTextView) {
        guard isAtEmptyLastLine(textView),
              CodeBlock.isCodeStyle(textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle) else { return }
        textView.typingAttributes = CodeBlock.bodyAttributes()
    }

    private static func isAtEmptyLastLine(_ textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        return selection.length == 0 && selection.location >= storage.length
            && (storage.length == 0 || (storage.string as NSString).character(at: storage.length - 1) == 0x0A)
    }

    /// Return in code: a fence line ("```") starts a code block, Return inside one adds a code line
    /// (empty lines included), and Return on a closing fence ends the block.
    /// Returns nil when the cursor is not in a code block or on a fence.
    private static func handleCodeNewline(in textView: NSTextView, selection: NSRange) -> Bool? {
        guard let storage = textView.textStorage else { return nil }
        let nsString = storage.string as NSString
        let atEmptyLastLine = selection.location == storage.length
            && (storage.length == 0 || nsString.character(at: storage.length - 1) == 0x0A)
        let paragraph = atEmptyLastLine
            ? NSRange(location: storage.length, length: 0)
            : nsString.paragraphRange(for: NSRange(location: min(selection.location, storage.length - 1), length: 0))
        let hasNewline = paragraph.length > 0 && nsString.character(at: NSMaxRange(paragraph) - 1) == 0x0A
        let content = NSRange(location: paragraph.location, length: paragraph.length - (hasNewline ? 1 : 0))
        let line = nsString.substring(with: content)
        let isCode = !atEmptyLastLine && CodeBlock.isCodeLine(in: storage, at: paragraph.location)

        /// Replaces the whole line with an empty one in the given style and puts the cursor on it.
        func resetLine(to attributes: [NSAttributedString.Key: Any]) -> Bool {
            let replacement = hasNewline ? "\n" : ""
            if paragraph.length > 0 {
                guard textView.shouldChangeText(in: paragraph, replacementString: replacement) else { return true }
                storage.replaceCharacters(in: paragraph, with: NSAttributedString(string: replacement, attributes: attributes))
            }
            textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
            textView.typingAttributes = attributes
            if paragraph.length > 0 { textView.didChangeText() }
            textView.needsDisplay = true
            return true
        }

        if isCode {
            if CodeBlock.isFence(line) {
                return resetLine(to: CodeBlock.bodyAttributes())
            }
            let attributes = CodeBlock.attributes()
            guard textView.shouldChangeText(in: selection, replacementString: "\n") else { return true }
            storage.replaceCharacters(in: selection, with: NSAttributedString(string: "\n", attributes: attributes))
            textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            textView.typingAttributes = attributes
            textView.didChangeText()
            return true
        }

        guard CodeBlock.isFence(line), selection.location == NSMaxRange(content) else { return nil }
        if hasNewline { return resetLine(to: CodeBlock.attributes()) }
        // At the end of the note, keep a real newline so the block has a line to draw.
        let attributes = CodeBlock.attributes()
        guard textView.shouldChangeText(in: paragraph, replacementString: "\n") else { return true }
        storage.replaceCharacters(in: paragraph, with: NSAttributedString(string: "\n", attributes: attributes))
        textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
        textView.typingAttributes = attributes
        textView.didChangeText()
        textView.needsDisplay = true
        return true
    }

    /// Backspace at the start of a code block's first line turns that line back into plain text.
    static func handleCodeBackspace(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, CodeBlock.isCodeLine(in: storage, at: selection.location) else { return false }
        let nsString = storage.string as NSString
        let paragraph = nsString.paragraphRange(for: NSRange(location: selection.location, length: 0))
        guard paragraph.location == selection.location else { return false }
        if paragraph.location > 0,
           CodeBlock.isCodeLine(in: storage, at: nsString.paragraphRange(for: NSRange(location: paragraph.location - 1, length: 0)).location) {
            return false
        }
        guard textView.shouldChangeText(in: paragraph, replacementString: nil) else { return true }
        storage.beginEditing()
        storage.addAttributes(CodeBlock.bodyAttributes(), range: paragraph)
        storage.endEditing()
        textView.typingAttributes = CodeBlock.bodyAttributes()
        textView.didChangeText()
        textView.needsDisplay = true
        return true
    }

    /// An item is empty only when nothing at all follows its marker; even a typed space counts as content.
    private static func isEmptyItem(_ paragraph: NSRange, markerLength: Int, in string: NSString) -> Bool {
        var end = NSMaxRange(paragraph)
        while end > paragraph.location, [0x0A, 0x0D, 0x2029].contains(string.character(at: end - 1)) {
            end -= 1
        }
        return end - paragraph.location <= markerLength
    }

    /// Return at the end of a heading starts a normal body paragraph.
    private static func endHeadingOnNewline(in textView: NSTextView, selection: NSRange) -> Bool {
        guard headingLevel(of: textView.typingAttributes[.font] as? NSFont) != nil else { return false }
        textView.insertText("\n", replacementRange: selection)
        var typing = textView.typingAttributes
        typing[.font] = NoteAppearance.bodyFont()
        textView.typingAttributes = typing
        return true
    }

    private static func font(in textView: NSTextView) -> NSFont {
        let selected = textView.selectedRange()
        if selected.length == 0 {
            return (textView.typingAttributes[.font] as? NSFont) ?? NoteAppearance.bodyFont()
        }
        if let storage = textView.textStorage, storage.length > 0 {
            let location = min(selected.location, storage.length - 1)
            return (storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont) ?? NoteAppearance.bodyFont()
        }
        return NoteAppearance.bodyFont()
    }

    private static func paragraphStarts(in string: String, selection: NSRange) -> [Int] {
        let nsString = string as NSString
        if nsString.length == 0 { return [0] }
        if selection.length == 0, selection.location == nsString.length, string.hasSuffix("\n") { return [nsString.length] }

        let safeLocation = min(selection.location, nsString.length - 1)
        let safeLength = min(selection.length, nsString.length - safeLocation)
        let encompassing = nsString.paragraphRange(for: NSRange(location: safeLocation, length: safeLength))
        var starts: [Int] = []
        var cursor = encompassing.location
        while cursor < NSMaxRange(encompassing), cursor < nsString.length {
            starts.append(cursor)
            let paragraph = nsString.paragraphRange(for: NSRange(location: cursor, length: 0))
            let next = NSMaxRange(paragraph)
            if next <= cursor { break }
            cursor = next
        }
        return starts
    }

    private static func hasBullet(in string: String, at location: Int) -> Bool {
        bulletMarker(in: string, at: location) != nil
    }

    private static func todoState(in string: String, at location: Int) -> TodoState {
        let nsString = string as NSString
        guard location + 2 <= nsString.length,
              nsString.substring(with: NSRange(location: location + 1, length: 1)) == " " else { return .plain }
        switch nsString.substring(with: NSRange(location: location, length: 1)) {
        case pendingTodoMarker: return .pending
        case completedTodoMarker: return .completed
        default: return .plain
        }
    }

    private static func applyTodoCompletion(_ completed: Bool, storage: NSTextStorage, paragraphStart: Int) {
        guard storage.length > 0, paragraphStart < storage.length else { return }
        let nsString = storage.string as NSString
        let paragraph = nsString.paragraphRange(for: NSRange(location: paragraphStart, length: 0))
        storage.removeAttribute(.strikethroughStyle, range: paragraph)
        guard completed else { return }

        let contentStart = min(paragraphStart + 2, NSMaxRange(paragraph))
        var contentEnd = NSMaxRange(paragraph)
        if contentEnd > contentStart,
           nsString.substring(with: NSRange(location: contentEnd - 1, length: 1)) == "\n" {
            contentEnd -= 1
        }
        guard contentEnd > contentStart else { return }
        storage.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: contentStart, length: contentEnd - contentStart)
        )
    }

    private static func setTypingTodoCompletion(_ completed: Bool, textView: NSTextView) {
        var typing = textView.typingAttributes
        if completed {
            typing[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            typing.removeValue(forKey: .strikethroughStyle)
        }
        textView.typingAttributes = typing
    }

    private static func bulletMarker(in string: String, at location: Int) -> String? {
        let nsString = string as NSString
        guard location + 2 <= nsString.length,
              nsString.substring(with: NSRange(location: location + 1, length: 1)) == " " else { return nil }
        let marker = nsString.substring(with: NSRange(location: location, length: 1))
        return (bulletMarkers + legacyBulletMarkers).contains(marker) ? marker : nil
    }

    private static func bulletMarker(for level: Int) -> String {
        bulletMarkers[min(max(0, level), bulletMarkers.count - 1)]
    }

    private static func applyListIndent(_ enabled: Bool, storage: NSTextStorage, location: Int) {
        guard storage.length > 0 else { return }
        let safeLocation = min(location, storage.length - 1)
        let range = (storage.string as NSString).paragraphRange(for: NSRange(location: safeLocation, length: 0))
        let existing = storage.attribute(.paragraphStyle, at: safeLocation, effectiveRange: nil) as? NSParagraphStyle
        let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        style.headIndent = enabled ? listIndentStep : 0
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private static func setTypingListIndent(_ enabled: Bool, textView: NSTextView) {
        setTypingListLevel(enabled ? 0 : nil, textView: textView)
    }

    private static func setTypingListLevel(_ level: Int?, textView: NSTextView) {
        var typing = textView.typingAttributes
        let existing = typing[.paragraphStyle] as? NSParagraphStyle
        let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = CGFloat(level ?? 0) * listIndentStep
        style.headIndent = level.map { CGFloat($0 + 1) * listIndentStep } ?? 0
        typing[.paragraphStyle] = style
        textView.typingAttributes = typing
    }

    private static func adjustSelection(location: inout Int, length: inout Int, changeAt: Int, delta: Int) {
        let originalLocation = location
        let originalEnd = location + length
        if length == 0 {
            if changeAt <= originalLocation { location = max(0, originalLocation + delta) }
        } else if changeAt < originalLocation {
            location = max(0, originalLocation + delta)
        } else if changeAt <= originalEnd {
            length = max(0, length + delta)
        }
    }

    private static func adjustedSelection(_ selection: NSRange, replacing range: NSRange, newLength: Int) -> NSRange {
        func adjust(_ offset: Int) -> Int {
            if offset <= range.location { return offset }
            if offset >= NSMaxRange(range) { return offset - range.length + newLength }
            return min(offset, range.location + newLength)
        }
        let start = adjust(selection.location)
        let end = adjust(NSMaxRange(selection))
        return NSRange(location: start, length: max(0, end - start))
    }
}
