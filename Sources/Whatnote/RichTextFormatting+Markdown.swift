import AppKit

/// Markdown typed or pasted into a note becomes rich text.
@MainActor
extension RichTextFormatting {
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
        // A Markdown checklist item copied from here or elsewhere: "- [ ] " or "- [x] ".
        let markdownTodo = pasted.length >= 6 && ["- [ ] ", "- [x] ", "- [X] "].contains(pasted.substring(to: 6))
        guard location > start,
              let markerLength = markdownTodo ? 6 : ListMarker.length(in: pasted, atParagraphStart: 0) else { return text }
        let pastesTodo = markdownTodo || TodoMarker.isCompleted(in: pasted, at: 0) != nil
        let afterMarker = ListMarker.length(in: string, atParagraphStart: start).map { start + $0 == location } ?? false
        guard pastesTodo || afterMarker else { return text }
        return pasted.substring(from: markerLength)
    }

    static let codeBackground = NSColor.black.withAlphaComponent(0.07)

    /// Converts Markdown syntax into rich text as it is typed or pasted:
    /// `# 标题`, `**粗体**`, `*斜体*`, `~~删除线~~`, `` `代码` ``, ```` ``` ```` 代码块, `[文字](网址)`, `- 列表`, `- [ ] 待办`.
    @discardableResult
    static func applyMarkdownSyntax(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, !textView.hasMarkedText() else { return false }
        var selection = textView.selectedRange()
        let originalTypingAttributes = textView.typingAttributes
        var headingTypingFont: NSFont?
        var changed = false
        // Text typed without a font (AppKit's small default) gets the body font.
        if NoteAppearance.repairFonts(in: storage) {
            var typing = textView.typingAttributes
            typing[.font] = NoteAppearance.noteFont(typing[.font] as? NSFont)
            textView.typingAttributes = typing
        }

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

        // An empty item whose marker is followed by another list's Markdown ("- ", "1. ", "[] ",
        // "【】 ") becomes that kind of item: drop the old marker and let the rules below apply.
        for match in matches(#"(?m)^(?:[☐☑•∘▪◦○] |\d{1,4}(?:\.\d{1,4})*\. )(?=[*-] |\d{1,4}\. |\[ ?\] |【】 )"#).reversed() {
            let start = match.range.location
            replace(match.range, with: NSAttributedString())
            applyListIndent(false, storage: storage, location: start)
            applyTodoCompletion(false, storage: storage, paragraphStart: start)
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

        // [] 待办 / 【】 待办 (also "[ ]")
        for match in matches(#"(?m)^(?:\[ ?\]|【】) "#).reversed() {
            let start = match.range.location
            var attributes = storage.attributes(at: start, effectiveRange: nil)
            attributes.removeValue(forKey: .strikethroughStyle)
            replace(match.range, with: NSAttributedString(string: "\(pendingTodoMarker) ", attributes: attributes))
            applyListIndent(false, storage: storage, location: start)
            applyTodoCompletion(false, storage: storage, paragraphStart: start)
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
}
