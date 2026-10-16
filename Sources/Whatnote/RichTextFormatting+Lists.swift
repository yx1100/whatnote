import AppKit

/// What bullet, numbered and task lists share: markers, nesting, Return and Backspace on items.
@MainActor
extension RichTextFormatting {
    static let listIndentStep: CGFloat = 18

    static let maximumListLevel = 8

    static let bulletMarkers = ["•", "∘", "▪"]

    static let legacyBulletMarkers = ["◦", "○"]

    static let pendingTodoMarker = "☐"

    static let completedTodoMarker = "☑"

    /// Inserts a list or to-do marker with the line's own font. A plain string inserted
    /// into an empty note would get AppKit's small default font, and later typing inherits it.
    static func insertMarker(_ marker: String, at location: Int, storage: NSTextStorage, textView: NSTextView) {
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
        let selectedStarts = paragraphStarts(in: storage.string, selection: originalSelection)
        let starts = selectedStarts.filter { hasBullet(in: storage.string, at: $0) }
        guard !starts.isEmpty else {
            if selectedStarts.contains(where: { todoState(in: storage.string, at: $0) != .plain }) {
                return adjustTodoLevel(in: textView, starts: selectedStarts, delta: delta)
            }
            if selectedStarts.contains(where: { orderedMarker(in: storage.string, at: $0) != nil }) {
                return adjustOrderedLevel(in: textView, starts: selectedStarts, delta: delta)
            }
            return false
        }

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

    static func previousBulletLevel(before start: Int, storage: NSTextStorage) -> Int? {
        guard start > 0, storage.length > 0 else { return nil }
        let previousRange = (storage.string as NSString).paragraphRange(for: NSRange(location: start - 1, length: 0))
        guard hasBullet(in: storage.string, at: previousRange.location) else { return nil }
        let style = storage.attribute(.paragraphStyle, at: previousRange.location, effectiveRange: nil) as? NSParagraphStyle
        return max(0, Int(round((style?.firstLineHeadIndent ?? 0) / listIndentStep)))
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

    static func isBulletList(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        return paragraphStarts(in: storage.string, selection: textView.selectedRange()).first.map {
            hasBullet(in: storage.string, at: $0)
        } ?? false
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
                var next = ordered.components
                next[next.count - 1] += 1
                textView.insertText("\n" + orderedMarkerText(next), replacementRange: selection)
                renumberOrderedBlock(around: selection.location + 1, in: textView)
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

    /// An item is empty only when nothing at all follows its marker; even a typed space counts as content.
    static func isEmptyItem(_ paragraph: NSRange, markerLength: Int, in string: NSString) -> Bool {
        var end = NSMaxRange(paragraph)
        while end > paragraph.location, LineBreak.isLineBreak(string.character(at: end - 1)) {
            end -= 1
        }
        return end - paragraph.location <= markerLength
    }

    static func paragraphStarts(in string: String, selection: NSRange) -> [Int] {
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

    static func hasBullet(in string: String, at location: Int) -> Bool {
        bulletMarker(in: string, at: location) != nil
    }

    static func bulletMarker(in string: String, at location: Int) -> String? {
        let nsString = string as NSString
        guard location + 2 <= nsString.length,
              nsString.substring(with: NSRange(location: location + 1, length: 1)) == " " else { return nil }
        let marker = nsString.substring(with: NSRange(location: location, length: 1))
        return (bulletMarkers + legacyBulletMarkers).contains(marker) ? marker : nil
    }

    static func bulletMarker(for level: Int) -> String {
        bulletMarkers[min(max(0, level), bulletMarkers.count - 1)]
    }

    static func applyListIndent(_ enabled: Bool, storage: NSTextStorage, location: Int) {
        guard storage.length > 0 else { return }
        let safeLocation = min(location, storage.length - 1)
        let range = (storage.string as NSString).paragraphRange(for: NSRange(location: safeLocation, length: 0))
        let existing = storage.attribute(.paragraphStyle, at: safeLocation, effectiveRange: nil) as? NSParagraphStyle
        let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        style.headIndent = enabled ? listIndentStep : 0
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }

    static func setTypingListIndent(_ enabled: Bool, textView: NSTextView) {
        setTypingListLevel(enabled ? 0 : nil, textView: textView)
    }

    static func setTypingListLevel(_ level: Int?, textView: NSTextView) {
        var typing = textView.typingAttributes
        let existing = typing[.paragraphStyle] as? NSParagraphStyle
        let style = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.firstLineHeadIndent = CGFloat(level ?? 0) * listIndentStep
        style.headIndent = level.map { CGFloat($0 + 1) * listIndentStep } ?? 0
        typing[.paragraphStyle] = style
        textView.typingAttributes = typing
    }

    /// Makes the wrapped lines of every list item start where the item's text starts, that is
    /// at the list's text column (see `ListMarker.textColumn`), the same for every kind of list. Returns whether anything changed.
    @discardableResult
    static func alignListContinuationLines(in storage: NSTextStorage) -> Bool {
        let string = storage.string as NSString
        var changes: [(range: NSRange, style: NSParagraphStyle)] = []
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(paragraph)
            guard !CodeBlock.isCodeLine(in: storage, at: paragraph.location),
                  ListMarker.length(in: string, atParagraphStart: paragraph.location) != nil,
                  let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            else { continue }
            let font = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont
                ?? NoteAppearance.bodyFont()
            let indent = style.firstLineHeadIndent
                + (ListMarker.textOffset(in: string, atParagraphStart: paragraph.location, font: font) ?? 0)
            guard abs(style.headIndent - indent) >= 0.5,
                  let aligned = style.mutableCopy() as? NSMutableParagraphStyle else { continue }
            aligned.headIndent = indent
            changes.append((paragraph, aligned))
        }
        guard !changes.isEmpty else { return false }
        storage.beginEditing()
        for change in changes { storage.addAttribute(.paragraphStyle, value: change.style, range: change.range) }
        storage.endEditing()
        return true
    }
}
