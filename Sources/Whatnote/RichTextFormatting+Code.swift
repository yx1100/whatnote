import AppKit

/// Code blocks.
@MainActor
extension RichTextFormatting {
    static func codeFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: NoteAppearance.bodyFontSize - 1, weight: .regular)
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

    static func leaveCodeStyleOnEmptyLastLine(in textView: NSTextView) {
        guard isAtEmptyLastLine(textView),
              CodeBlock.isCodeStyle(textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle) else { return }
        textView.typingAttributes = CodeBlock.bodyAttributes()
    }

    /// Return in code: a fence line ("```") starts a code block, Return inside one adds a code line
    /// (empty lines included), and Return on a closing fence ends the block.
    /// Returns nil when the cursor is not in a code block or on a fence.
    static func handleCodeNewline(in textView: NSTextView, selection: NSRange) -> Bool? {
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
}
