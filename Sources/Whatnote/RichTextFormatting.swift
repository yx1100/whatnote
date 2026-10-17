import AppKit

/// Inline styles (bold, italic), headings, dividers and the helpers the other parts share.
@MainActor
enum RichTextFormatting {
    enum TodoState: Equatable {
        case plain
        case pending
        case completed
    }

    static func toggleBold(in textView: NSTextView) {
        toggleFontTrait(.boldFontMask, in: textView)
    }

    static func toggleItalic(in textView: NSTextView) {
        toggleFontTrait(.italicFontMask, in: textView)
    }

    static func toggleFontTrait(_ trait: NSFontTraitMask, in textView: NSTextView) {
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

    static func isBold(in textView: NSTextView) -> Bool {
        NSFontManager.shared.traits(of: font(in: textView)).contains(.boldFontMask)
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
    static func dividerParagraph(containing location: Int, in storage: NSTextStorage) -> NSRange? {
        let string = storage.string as NSString
        guard location >= 0, location < string.length,
              !CodeBlock.isCodeLine(in: storage, at: location) else { return nil }
        let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
        var content = paragraph
        while content.length > 0, LineBreak.isLineBreak(string.character(at: NSMaxRange(content) - 1)) {
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

    /// Heading sizes for #, ## and ###. They must stay clear of every size in `legacySizes`.
    static let headingSizes: [CGFloat] = [28, 23, 21]

    static func headingFont(level: Int) -> NSFont {
        let clamped = min(max(level, 1), headingSizes.count)
        return NSFont.systemFont(ofSize: headingSizes[clamped - 1], weight: clamped == 3 ? .semibold : .bold)
    }

    static func headingLevel(of font: NSFont?) -> Int? {
        guard let font else { return nil }
        return headingSizes.firstIndex(where: { abs($0 - font.pointSize) < 0.5 }).map { $0 + 1 }
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

    static func isAtEmptyLastLine(_ textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        return selection.length == 0 && selection.location >= storage.length
            && (storage.length == 0 || (storage.string as NSString).character(at: storage.length - 1) == 0x0A)
    }

    /// Return at the end of a heading starts a normal body paragraph.
    static func endHeadingOnNewline(in textView: NSTextView, selection: NSRange) -> Bool {
        guard headingLevel(of: textView.typingAttributes[.font] as? NSFont) != nil else { return false }
        textView.insertText("\n", replacementRange: selection)
        var typing = textView.typingAttributes
        typing[.font] = NoteAppearance.bodyFont()
        textView.typingAttributes = typing
        return true
    }

    static func font(in textView: NSTextView) -> NSFont {
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

    static func adjustSelection(location: inout Int, length: inout Int, changeAt: Int, delta: Int) {
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

    static func adjustedSelection(_ selection: NSRange, replacing range: NSRange, newLength: Int) -> NSRange {
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
