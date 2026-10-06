import AppKit
import CoreText

@main
struct RichTextProbe {
    @MainActor
    static func main() {
        func markerDiameter(_ symbol: String) -> CGFloat {
            let baseFont = NoteAppearance.bodyFont() as CTFont
            let value = symbol as CFString
            let font = CTFontCreateForString(
                baseFont,
                value,
                CFRange(location: 0, length: CFStringGetLength(value))
            )
            var characters = Array(symbol.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
            var glyph = glyphs[0]
            return CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, nil, 1).height
        }

        let filledDiameter = markerDiameter("•")
        let ringDiameter = markerDiameter("∘")
        let squareDiameter = markerDiameter("▪")
        let markerProportionsAreBalanced = (1.45...1.75).contains(ringDiameter / filledDiameter)
            && (1.0...1.5).contains(squareDiameter / filledDiameter)

        let value = NSMutableAttributedString(string: "重点\n第二段")
        let bold = NSFontManager.shared.convert(NoteAppearance.bodyFont(), toHaveTrait: .boldFontMask)
        value.addAttribute(.font, value: bold, range: NSRange(location: 0, length: 2))
        value.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 3, length: 3))
        value.replaceCharacters(in: NSRange(location: 3, length: 0), with: "• ")

        guard let data = RichTextCodec.encode(value), let restored = RichTextCodec.decode(data) else { exit(1) }
        let restoredFont = restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let boldSurvived = restoredFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
        let bulletSurvived = restored.string.contains("• 第二段")
        let strikeSurvived = (restored.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue

        let editor = NSTextView()
        editor.isRichText = true
        editor.string = "普通文本"
        editor.typingAttributes = [.font: NoteAppearance.bodyFont()]
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        RichTextFormatting.toggleBold(in: editor)
        let futureBoldOn = RichTextFormatting.isBold(in: editor)
        RichTextFormatting.toggleBold(in: editor)
        let futureBoldOff = !RichTextFormatting.isBold(in: editor)

        let todoEditor = NSTextView()
        todoEditor.isRichText = true
        todoEditor.string = "第一项\n第二项"
        todoEditor.setSelectedRange(NSRange(location: 0, length: todoEditor.string.utf16.count))
        RichTextFormatting.toggleTodo(in: todoEditor)
        let todoPending = todoEditor.string == "☐ 第一项\n☐ 第二项"
            && RichTextFormatting.todoState(in: todoEditor) == .pending
        // Checking happens by clicking the circle, not with the to-do button.
        RichTextFormatting.toggleTodoCompletion(atParagraphStart: 0, in: todoEditor)
        RichTextFormatting.toggleTodoCompletion(atParagraphStart: 6, in: todoEditor)
        let firstTaskTextRange = NSRange(location: 2, length: 3)
        let firstTaskStrike = (todoEditor.textStorage?.attribute(.strikethroughStyle, at: firstTaskTextRange.location, effectiveRange: nil) as? NSNumber)?.intValue
        let todoCompleted = todoEditor.string == "☑ 第一项\n☑ 第二项"
            && RichTextFormatting.todoState(in: todoEditor) == .completed
            && firstTaskStrike == NSUnderlineStyle.single.rawValue
            && todoEditor.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil
        let completedRoundTrip = todoEditor.textStorage
            .flatMap(RichTextCodec.encode)
            .flatMap(RichTextCodec.decode)
        let todoSurvived = completedRoundTrip?.string == todoEditor.string
            && (completedRoundTrip?.attribute(.strikethroughStyle, at: firstTaskTextRange.location, effectiveRange: nil) as? NSNumber)?.intValue == NSUnderlineStyle.single.rawValue
        // The button removes to-dos whether or not they are checked.
        RichTextFormatting.toggleTodo(in: todoEditor)
        let todoRemoved = todoEditor.string == "第一项\n第二项"
            && RichTextFormatting.todoState(in: todoEditor) == .plain
            && todoEditor.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil
        let todoSelectionPreserved = todoEditor.selectedRange() == NSRange(location: 0, length: todoEditor.string.utf16.count)
        print("todo parts: pending=\(todoPending) completed=\(todoCompleted) survived=\(todoSurvived) removed=\(todoRemoved) selection=\(todoSelectionPreserved) \(todoEditor.selectedRange())")

        let completedTodoNewlineEditor = NSTextView()
        completedTodoNewlineEditor.isRichText = true
        completedTodoNewlineEditor.string = "☑ 已完成"
        completedTodoNewlineEditor.textStorage?.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 2, length: 3)
        )
        completedTodoNewlineEditor.typingAttributes = [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        completedTodoNewlineEditor.setSelectedRange(NSRange(location: completedTodoNewlineEditor.string.utf16.count, length: 0))
        let continuedTodo = RichTextFormatting.handleStructuredNewline(in: completedTodoNewlineEditor)
        let completedTodoNewline = continuedTodo
            && completedTodoNewlineEditor.string == "☑ 已完成\n☐ "
            && completedTodoNewlineEditor.typingAttributes[.strikethroughStyle] == nil
            && completedTodoNewlineEditor.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) != nil
            && completedTodoNewlineEditor.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) == nil

        let splitCompletedTodoEditor = NSTextView()
        splitCompletedTodoEditor.isRichText = true
        splitCompletedTodoEditor.string = "☑ 前后"
        splitCompletedTodoEditor.textStorage?.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 2, length: 2)
        )
        splitCompletedTodoEditor.typingAttributes = [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        splitCompletedTodoEditor.setSelectedRange(NSRange(location: 3, length: 0))
        let splitTodo = RichTextFormatting.handleStructuredNewline(in: splitCompletedTodoEditor)
        let splitCompletedTodo = splitTodo
            && splitCompletedTodoEditor.string == "☑ 前\n☐ 后"
            && splitCompletedTodoEditor.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) != nil
            && splitCompletedTodoEditor.textStorage?.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) == nil
        print("todo newline parts: continued=\(completedTodoNewline) split=\(splitCompletedTodo) strings=\(completedTodoNewlineEditor.string.debugDescription) \(splitCompletedTodoEditor.string.debugDescription)")

        let bulletEditor = NSTextView()
        bulletEditor.isRichText = true
        bulletEditor.string = "第一项\n第二项"
        bulletEditor.setSelectedRange(NSRange(location: 0, length: bulletEditor.string.utf16.count))
        RichTextFormatting.toggleBulletList(in: bulletEditor)
        let bulletsOn = bulletEditor.string == "• 第一项\n• 第二项"
        RichTextFormatting.toggleBulletList(in: bulletEditor)
        let bulletsOff = bulletEditor.string == "第一项\n第二项"
        let bulletSelectionPreserved = bulletEditor.selectedRange() == NSRange(location: 0, length: bulletEditor.string.utf16.count)

        let listModeEditor = NSTextView()
        listModeEditor.isRichText = true
        listModeEditor.string = "• 项目"
        listModeEditor.setSelectedRange(NSRange(location: listModeEditor.string.utf16.count, length: 0))
        RichTextFormatting.toggleTodo(in: listModeEditor)
        let bulletBecameTodo = listModeEditor.string == "☐ 项目"
            && RichTextFormatting.todoState(in: listModeEditor) == .pending
            && !RichTextFormatting.isBulletList(in: listModeEditor)
        RichTextFormatting.toggleBulletList(in: listModeEditor)
        let todoBecameBullet = listModeEditor.string == "• 项目"
            && RichTextFormatting.todoState(in: listModeEditor) == .plain
            && RichTextFormatting.isBulletList(in: listModeEditor)

        let markdownEditor = NSTextView()
        markdownEditor.isRichText = true
        markdownEditor.font = NoteAppearance.bodyFont()
        markdownEditor.string = "**重点**\n- 第一项\n* 第二项"
        markdownEditor.setSelectedRange(NSRange(location: markdownEditor.string.utf16.count, length: 0))
        let markdownChanged = RichTextFormatting.applyMarkdownSyntax(in: markdownEditor)
        let markdownFont = markdownEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let markdownBold = markdownFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
        let markdownBullets = markdownEditor.string == "重点\n• 第一项\n• 第二项"

        func convertedEditor(_ text: String) -> NSTextView {
            let editor = NSTextView()
            editor.isRichText = true
            editor.font = NoteAppearance.bodyFont()
            editor.typingAttributes = [.font: NoteAppearance.bodyFont()]
            editor.string = text
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            _ = RichTextFormatting.applyMarkdownSyntax(in: editor)
            return editor
        }
        func fontAt(_ editor: NSTextView, _ location: Int) -> NSFont? {
            editor.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        }

        let strikeEditor = convertedEditor("~~删除~~")
        let strikeMarkdown = strikeEditor.string == "删除"
            && (strikeEditor.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue

        let headingEditor = convertedEditor("## 标题")
        let headingMarkdown = headingEditor.string == "标题"
            && RichTextFormatting.headingLevel(of: fontAt(headingEditor, 0)) == 2
            && RichTextFormatting.headingLevel(of: headingEditor.typingAttributes[.font] as? NSFont) == 2

        let italicEditor = convertedEditor("一个*斜体*词")
        let italicMarkdown = italicEditor.string == "一个斜体词"
            && fontAt(italicEditor, 2).map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } == true
        let arithmeticUntouched = convertedEditor("2*3*4").string == "2*3*4"

        let codeEditor = convertedEditor("运行 `swift build`")
        let codeMarkdown = codeEditor.string == "运行 swift build"
            && fontAt(codeEditor, 3)?.isFixedPitch == true

        let linkEditor = convertedEditor("见 [官网](https://example.com)")
        let linkMarkdown = linkEditor.string == "见 官网"
            && (linkEditor.textStorage?.attribute(.link, at: 2, effectiveRange: nil) as? URL)?.absoluteString == "https://example.com"
        let nonLinkUntouched = convertedEditor("[注释](不是网址)").string == "[注释](不是网址)"

        let todoMarkdownEditor = convertedEditor("- [ ] 买牛奶\n- [x] 已完成")
        let todoMarkdown = todoMarkdownEditor.string == "☐ 买牛奶\n☑ 已完成"

        // Clicking a checkbox flips only that item between open and done.
        let clickEditor = NSTextView()
        clickEditor.isRichText = true
        clickEditor.allowsUndo = true
        clickEditor.string = "☐ 买牛奶\n☑ 已完成"
        let firstChecked = RichTextFormatting.toggleTodoCompletion(atParagraphStart: 0, in: clickEditor)
            && clickEditor.string == "☑ 买牛奶\n☑ 已完成"
            && (clickEditor.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue
        let secondUnchecked = RichTextFormatting.toggleTodoCompletion(atParagraphStart: 6, in: clickEditor)
            && clickEditor.string == "☑ 买牛奶\n☐ 已完成"
            && clickEditor.textStorage?.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) == nil
        let plainIgnored = !RichTextFormatting.toggleTodoCompletion(atParagraphStart: 2, in: clickEditor)
        // Backspace right after a marker removes the whole marker instead of leaving "☐".
        let backspaceEditor = NSTextView()
        backspaceEditor.isRichText = true
        backspaceEditor.allowsUndo = true
        backspaceEditor.string = "☐ \n• 列表"
        backspaceEditor.setSelectedRange(NSRange(location: 2, length: 0))
        let todoBackspace = RichTextFormatting.handleMarkerBackspace(in: backspaceEditor)
            && backspaceEditor.string == "\n• 列表"
        backspaceEditor.setSelectedRange(NSRange(location: 3, length: 0))
        let bulletBackspace = RichTextFormatting.handleMarkerBackspace(in: backspaceEditor)
            && backspaceEditor.string == "\n列表"
        backspaceEditor.setSelectedRange(NSRange(location: 2, length: 0))
        let ordinaryBackspace = !RichTextFormatting.handleMarkerBackspace(in: backspaceEditor)

        // Lines broken by older versions ("☐123") become to-dos again.
        let repairEditor = NSTextView()
        repairEditor.isRichText = true
        repairEditor.string = "☐123\n☑"
        let repaired = RichTextFormatting.normalizeTodoMarkers(in: repairEditor)
            && repairEditor.string == "☐ 123\n☑ "
            && !RichTextFormatting.normalizeTodoMarkers(in: repairEditor)

        // The to-do button toggles between to-do and plain, never checking the item.
        let buttonEditor = NSTextView()
        buttonEditor.isRichText = true
        buttonEditor.string = "任务"
        buttonEditor.setSelectedRange(NSRange(location: 0, length: 0))
        RichTextFormatting.toggleTodo(in: buttonEditor)
        let buttonAdds = buttonEditor.string == "☐ 任务"
        RichTextFormatting.toggleTodo(in: buttonEditor)
        let buttonRemoves = buttonEditor.string == "任务"

        // In an empty note the marker keeps the note's font instead of AppKit's default.
        let noteFont = NSFont.systemFont(ofSize: 18)
        for toggle in [RichTextFormatting.toggleTodo(in:), RichTextFormatting.toggleBulletList(in:)] {
            let emptyEditor = NSTextView()
            emptyEditor.isRichText = true
            emptyEditor.typingAttributes = [.font: noteFont]
            toggle(emptyEditor)
            guard (emptyEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18,
                  (emptyEditor.typingAttributes[.font] as? NSFont)?.pointSize == 18 else { exit(3) }
        }

        // Numbered lists: the button numbers lines, Return continues and renumbers,
        // Return on an empty item and backspace after the number end the item.
        let orderedEditor = NSTextView()
        orderedEditor.isRichText = true
        orderedEditor.allowsUndo = true
        orderedEditor.string = "买菜\n做饭"
        orderedEditor.setSelectedRange(NSRange(location: 0, length: orderedEditor.string.utf16.count))
        RichTextFormatting.toggleOrderedList(in: orderedEditor)
        let orderedOn = orderedEditor.string == "1. 买菜\n2. 做饭" && RichTextFormatting.isOrderedList(in: orderedEditor)
        orderedEditor.setSelectedRange(NSRange(location: 5, length: 0))
        let orderedContinues = RichTextFormatting.handleStructuredNewline(in: orderedEditor)
            && orderedEditor.string == "1. 买菜\n2. \n3. 做饭"
        let orderedEmptyEnds = RichTextFormatting.handleStructuredNewline(in: orderedEditor)
            && orderedEditor.string == "1. 买菜\n\n3. 做饭"
        orderedEditor.setSelectedRange(NSRange(location: 10, length: 0))
        let orderedBackspace = RichTextFormatting.handleMarkerBackspace(in: orderedEditor)
            && orderedEditor.string == "1. 买菜\n\n做饭"
        orderedEditor.setSelectedRange(NSRange(location: 0, length: orderedEditor.string.utf16.count))
        RichTextFormatting.toggleOrderedList(in: orderedEditor)
        let orderedMixed = orderedEditor.string == "1. 买菜\n2. \n3. 做饭"
        RichTextFormatting.toggleOrderedList(in: orderedEditor)
        let orderedOff = orderedEditor.string == "买菜\n\n做饭"
        let orderedList = orderedOn && orderedContinues && orderedEmptyEnds && orderedBackspace && orderedMixed && orderedOff

        // Dividers: "---" on its own line; the button puts one on its own line and moves below it.
        let dividerPatterns = DividerLine.isDivider("---") && DividerLine.isDivider("*****") && DividerLine.isDivider("___")
            && !DividerLine.isDivider("--") && !DividerLine.isDivider("--- 文字") && !DividerLine.isDivider("- - -")
        let dividerEditor = NSTextView()
        dividerEditor.isRichText = true
        dividerEditor.string = "上文下文"
        dividerEditor.setSelectedRange(NSRange(location: 2, length: 0))
        RichTextFormatting.insertDivider(in: dividerEditor)
        let dividerMidLine = dividerEditor.string == "上文\n---\n下文" && dividerEditor.selectedRange().location == 7
        let dividerRanges = DividerLine.ranges(
            in: dividerEditor.string as NSString,
            overlapping: NSRange(location: 0, length: dividerEditor.string.utf16.count)
        ) == [NSRange(location: 3, length: 3)]
        let emptyDividerEditor = NSTextView()
        emptyDividerEditor.isRichText = true
        RichTextFormatting.insertDivider(in: emptyDividerEditor)
        let dividerEmpty = emptyDividerEditor.string == "---\n"
            && (emptyDividerEditor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == NoteAppearance.bodyFontSize
        let dividers = dividerPatterns && dividerMidLine && dividerRanges && dividerEmpty

        // A list item holding only a typed space is not empty: Return starts the next item.
        var spaceContinues = true
        for (text, expected) in [("• ", "• \n• "), ("☐ ", "☐ \n☐ "), ("1. ", "1. \n2. ")] {
            let editor = NSTextView()
            editor.isRichText = true
            editor.string = text + " "
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            spaceContinues = spaceContinues
                && RichTextFormatting.handleStructuredNewline(in: editor)
                && editor.string == text + " " + String(expected.dropFirst(text.count))
        }
        var emptyEnds = true
        for text in ["• ", "☐ ", "1. "] {
            let editor = NSTextView()
            editor.isRichText = true
            editor.string = text
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            emptyEnds = emptyEnds && RichTextFormatting.handleStructuredNewline(in: editor) && editor.string.isEmpty
        }

        let checkboxClicks = firstChecked && secondUnchecked && plainIgnored && buttonAdds && buttonRemoves && orderedList && dividers && spaceContinues && emptyEnds
            && todoBackspace && bulletBackspace && ordinaryBackspace && repaired

        let extendedMarkdown = strikeMarkdown && headingMarkdown && italicMarkdown && arithmeticUntouched
            && codeMarkdown && linkMarkdown && nonLinkUntouched && todoMarkdown

        let boldMarkdownEditor = NSTextView()
        boldMarkdownEditor.isRichText = true
        boldMarkdownEditor.font = NoteAppearance.bodyFont()
        boldMarkdownEditor.typingAttributes = [.font: NoteAppearance.bodyFont()]
        boldMarkdownEditor.string = "**重点**"
        boldMarkdownEditor.setSelectedRange(NSRange(location: boldMarkdownEditor.string.utf16.count, length: 0))
        _ = RichTextFormatting.applyMarkdownSyntax(in: boldMarkdownEditor)
        boldMarkdownEditor.insertText(" 后续", replacementRange: boldMarkdownEditor.selectedRange())
        let trailingFont = boldMarkdownEditor.textStorage?.attribute(.font, at: boldMarkdownEditor.string.utf16.count - 1, effectiveRange: nil) as? NSFont
        let trailingIsRegular = trailingFont.map { !NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false

        let emptyBulletEditor = NSTextView()
        emptyBulletEditor.isRichText = true
        emptyBulletEditor.string = "• "
        let listStyle = NSMutableParagraphStyle()
        listStyle.headIndent = 18
        emptyBulletEditor.textStorage?.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: 0, length: 2))
        emptyBulletEditor.typingAttributes = [.font: NoteAppearance.bodyFont(), .paragraphStyle: listStyle]
        emptyBulletEditor.setSelectedRange(NSRange(location: 2, length: 0))
        let exitedEmptyBullet = RichTextFormatting.handleStructuredNewline(in: emptyBulletEditor)
        let exitStyle = emptyBulletEditor.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        let listExitClean = exitedEmptyBullet && emptyBulletEditor.string.isEmpty && (exitStyle?.headIndent ?? 0) == 0

        let nestedBulletEditor = NSTextView()
        nestedBulletEditor.isRichText = true
        nestedBulletEditor.string = "• 父级\n• 子项一\n• 子项二"
        nestedBulletEditor.setSelectedRange(NSRange(location: 5, length: 11))
        let indented = RichTextFormatting.adjustBulletLevel(in: nestedBulletEditor, delta: 1)
        let firstNestedStyle = nestedBulletEditor.textStorage?.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        let secondNestedStyle = nestedBulletEditor.textStorage?.attribute(.paragraphStyle, at: 11, effectiveRange: nil) as? NSParagraphStyle
        let multiLevelOn = indented
            && nestedBulletEditor.string == "• 父级\n∘ 子项一\n∘ 子项二"
            && firstNestedStyle?.firstLineHeadIndent == 18
            && firstNestedStyle?.headIndent == 36
            && secondNestedStyle?.firstLineHeadIndent == 18
            && secondNestedStyle?.headIndent == 36
        let nestedRoundTrip = RichTextCodec.encode(nestedBulletEditor.attributedString())
            .flatMap(RichTextCodec.decode)
        let restoredNestedStyle = nestedRoundTrip?.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        let multiLevelSurvived = restoredNestedStyle?.firstLineHeadIndent == 18
            && restoredNestedStyle?.headIndent == 36
        let outdented = RichTextFormatting.adjustBulletLevel(in: nestedBulletEditor, delta: -1)
        let rootStyle = nestedBulletEditor.textStorage?.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        let multiLevelOff = outdented && rootStyle?.firstLineHeadIndent == 0 && rootStyle?.headIndent == 18
            && nestedBulletEditor.string == "• 父级\n• 子项一\n• 子项二"

        let deepBulletEditor = NSTextView()
        deepBulletEditor.isRichText = true
        deepBulletEditor.string = "• 根\n• 一级\n• 二级\n• 三级"
        deepBulletEditor.setSelectedRange(NSRange(location: 6, length: 0))
        _ = RichTextFormatting.adjustBulletLevel(in: deepBulletEditor, delta: 1)
        deepBulletEditor.setSelectedRange(NSRange(location: 11, length: 0))
        _ = RichTextFormatting.adjustBulletLevel(in: deepBulletEditor, delta: 1)
        _ = RichTextFormatting.adjustBulletLevel(in: deepBulletEditor, delta: 1)
        deepBulletEditor.setSelectedRange(NSRange(location: 16, length: 0))
        _ = RichTextFormatting.adjustBulletLevel(in: deepBulletEditor, delta: 1)
        _ = RichTextFormatting.adjustBulletLevel(in: deepBulletEditor, delta: 1)
        _ = RichTextFormatting.adjustBulletLevel(in: deepBulletEditor, delta: 1)
        let tieredMarkers = deepBulletEditor.string == "• 根\n∘ 一级\n▪ 二级\n▪ 三级"

        let inheritedMarkerEditor = NSTextView()
        inheritedMarkerEditor.isRichText = true
        inheritedMarkerEditor.string = "• 父级\n∘ 子项"
        let inheritedStyle = NSMutableParagraphStyle()
        inheritedStyle.firstLineHeadIndent = 18
        inheritedStyle.headIndent = 36
        inheritedMarkerEditor.textStorage?.addAttribute(.paragraphStyle, value: inheritedStyle, range: NSRange(location: 5, length: 4))
        inheritedMarkerEditor.typingAttributes = [.font: NoteAppearance.bodyFont(), .paragraphStyle: inheritedStyle]
        inheritedMarkerEditor.setSelectedRange(NSRange(location: inheritedMarkerEditor.string.utf16.count, length: 0))
        let insertedNestedLine = RichTextFormatting.handleStructuredNewline(in: inheritedMarkerEditor)
        let inheritedMarker = insertedNestedLine && inheritedMarkerEditor.string.hasSuffix("\n∘ ")

        let legacyMarkerEditor = NSTextView()
        legacyMarkerEditor.isRichText = true
        legacyMarkerEditor.string = "• 父级\n◦ 小圆旧版\n○ 大圆旧版"
        legacyMarkerEditor.textStorage?.addAttribute(
            .paragraphStyle,
            value: inheritedStyle,
            range: NSRange(location: 5, length: legacyMarkerEditor.string.utf16.count - 5)
        )
        let normalizedLegacyMarker = RichTextFormatting.normalizeBulletMarkers(in: legacyMarkerEditor)
            && legacyMarkerEditor.string == "• 父级\n∘ 小圆旧版\n∘ 大圆旧版"

        let orphanBulletEditor = NSTextView()
        orphanBulletEditor.isRichText = true
        orphanBulletEditor.string = "• 首项"
        orphanBulletEditor.setSelectedRange(NSRange(location: 2, length: 0))
        let orphanPrevented = !RichTextFormatting.adjustBulletLevel(in: orphanBulletEditor, delta: 1)

        // Code blocks: "```" and Return starts one, Markdown inside stays as typed, Return on an
        // empty line stays in the block, a closing fence ends it, Backspace on its first line
        // undoes it, and it survives saving.
        let codeBlockEditor = NSTextView()
        codeBlockEditor.isRichText = true
        codeBlockEditor.allowsUndo = true
        codeBlockEditor.typingAttributes = [.font: NoteAppearance.bodyFont()]
        codeBlockEditor.string = "说明\n```"
        codeBlockEditor.setSelectedRange(NSRange(location: codeBlockEditor.string.utf16.count, length: 0))
        let codeStorage = codeBlockEditor.textStorage!
        let fenceStarted = RichTextFormatting.handleStructuredNewline(in: codeBlockEditor)
            && codeBlockEditor.string == "说明\n\n"
            && CodeBlock.isCodeLine(in: codeStorage, at: 3)
            && codeBlockEditor.selectedRange().location == 3
        codeBlockEditor.insertText("**x** = 1", replacementRange: codeBlockEditor.selectedRange())
        _ = RichTextFormatting.applyMarkdownSyntax(in: codeBlockEditor)
        let codeKeepsMarkdown = codeBlockEditor.string == "说明\n**x** = 1\n"
            && fontAt(codeBlockEditor, 3)?.isFixedPitch == true
        let codeContinues = RichTextFormatting.handleStructuredNewline(in: codeBlockEditor)
            && codeBlockEditor.string == "说明\n**x** = 1\n\n"
            && CodeBlock.isCodeLine(in: codeStorage, at: 13)
        // An empty line stays in the block; only a closing fence ends it.
        let emptyLineContinues = RichTextFormatting.handleStructuredNewline(in: codeBlockEditor)
            && codeBlockEditor.string == "说明\n**x** = 1\n\n\n"
            && CodeBlock.isCodeLine(in: codeStorage, at: 14)
        codeBlockEditor.insertText("```", replacementRange: codeBlockEditor.selectedRange())
        let codeEnds = emptyLineContinues
            && RichTextFormatting.handleStructuredNewline(in: codeBlockEditor)
            && codeBlockEditor.string == "说明\n**x** = 1\n\n\n"
            && CodeBlock.isCodeLine(in: codeStorage, at: 3)
            && CodeBlock.isCodeLine(in: codeStorage, at: 13)
            && !CodeBlock.isCodeLine(in: codeStorage, at: 14)
            && codeBlockEditor.selectedRange().location == 14
        let codeRoundTrip = RichTextCodec.encode(codeBlockEditor.attributedString())
            .flatMap(RichTextCodec.decode)
            .map { CodeBlock.isCodeLine(in: $0, at: 3) && !CodeBlock.isCodeLine(in: $0, at: 0) } ?? false
        codeBlockEditor.setSelectedRange(NSRange(location: 3, length: 0))
        let codeBackspace = RichTextFormatting.handleCodeBackspace(in: codeBlockEditor)
            && !CodeBlock.isCodeLine(in: codeStorage, at: 3)
            && codeBlockEditor.string == "说明\n**x** = 1\n\n\n"

        // Clicking the empty line after a block at the end of the note types plain text.
        let trailingEditor = NSTextView()
        trailingEditor.isRichText = true
        RichTextFormatting.toggleCodeBlock(in: trailingEditor)
        trailingEditor.setSelectedRange(NSRange(location: 1, length: 0))
        trailingEditor.typingAttributes = CodeBlock.attributes()
        RichTextFormatting.leaveCodeStyleOnEmptyLastLine(in: trailingEditor)
        let trailingLinePlain = !CodeBlock.isCodeStyle(trailingEditor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
            && !RichTextFormatting.isCodeBlock(in: trailingEditor)
            && CodeBlock.isCodeLine(in: trailingEditor.textStorage!, at: 0)
        print("codeBlock trailingPlain=\(trailingLinePlain)")

        let pastedCodeEditor = convertedEditor("前\n```swift\nlet a = 1\n# 不是标题\n```\n后")
        let pastedCodeStorage = pastedCodeEditor.textStorage!
        let pastedCode = pastedCodeEditor.string == "前\nlet a = 1\n# 不是标题\n后"
            && !CodeBlock.isCodeLine(in: pastedCodeStorage, at: 0)
            && CodeBlock.isCodeLine(in: pastedCodeStorage, at: 2)
            && CodeBlock.isCodeLine(in: pastedCodeStorage, at: 12)
            && !CodeBlock.isCodeLine(in: pastedCodeStorage, at: 19)
            && CodeBlock.blocks(in: pastedCodeStorage, overlapping: NSRange(location: 14, length: 1)) == [NSRange(location: 2, length: 17)]
        let codeButtonEditor = NSTextView()
        codeButtonEditor.isRichText = true
        codeButtonEditor.string = "甲\n乙\n丙"
        codeButtonEditor.setSelectedRange(NSRange(location: 0, length: 3))
        RichTextFormatting.toggleCodeBlock(in: codeButtonEditor)
        let codeButtonStorage = codeButtonEditor.textStorage!
        let codeButtonOn = CodeBlock.isCodeLine(in: codeButtonStorage, at: 0)
            && CodeBlock.isCodeLine(in: codeButtonStorage, at: 2)
            && !CodeBlock.isCodeLine(in: codeButtonStorage, at: 4)
            && RichTextFormatting.isCodeBlock(in: codeButtonEditor)
            && CodeBlock.isFirstLine(in: codeButtonStorage, at: 0)
            && !CodeBlock.isFirstLine(in: codeButtonStorage, at: 2)
        RichTextFormatting.toggleCodeBlock(in: codeButtonEditor)
        let codeButtonOff = !CodeBlock.isCodeLine(in: codeButtonStorage, at: 0)
            && !CodeBlock.isCodeLine(in: codeButtonStorage, at: 2)
            && codeButtonEditor.string == "甲\n乙\n丙"
        let emptyCodeEditor = NSTextView()
        emptyCodeEditor.isRichText = true
        RichTextFormatting.toggleCodeBlock(in: emptyCodeEditor)
        let emptyCodeStarted = emptyCodeEditor.string == "\n"
            && CodeBlock.isCodeLine(in: emptyCodeEditor.textStorage!, at: 0)
            && emptyCodeEditor.selectedRange().location == 0
        let codeButton = codeButtonOn && codeButtonOff && emptyCodeStarted
        print("codeButton on=\(codeButtonOn) off=\(codeButtonOff) empty=\(emptyCodeStarted)")

        // The cursor rests only at a divider's left end. Backspace below a divider deletes its last
        // dash; at its left end Backspace is left to AppKit, which joins it to the line above.
        let dividerCursorEditor = NSTextView()
        dividerCursorEditor.isRichText = true
        dividerCursorEditor.string = "上\n---\n下"
        func snapped(_ location: Int, from old: Int, userMove: Bool = true) -> Int {
            RichTextFormatting.selectionAvoidingDividers(
                NSRange(location: location, length: 0),
                from: NSRange(location: old, length: 0),
                isUserMove: userMove,
                in: dividerCursorEditor
            ).location
        }
        let clickedDivider = snapped(3, from: 0) == 2 && snapped(4, from: 7) == 2
        let backIntoDivider = snapped(5, from: 6) == 2
        let rightFromDivider = snapped(3, from: 2) == 6
        let plainLineUntouched = snapped(7, from: 0) == 7 && snapped(2, from: 0) == 2
        let typingDividerUntouched = snapped(5, from: 4, userMove: false) == 5
        dividerCursorEditor.setSelectedRange(NSRange(location: 6, length: 0))
        let backspaceBelow = RichTextFormatting.handleDividerBackspace(in: dividerCursorEditor)
            && dividerCursorEditor.string == "上\n--\n下"
            && dividerCursorEditor.selectedRange().location == 4
        dividerCursorEditor.string = "上\n---\n下"
        dividerCursorEditor.setSelectedRange(NSRange(location: 2, length: 0))
        let backspaceAtDivider = !RichTextFormatting.handleDividerBackspace(in: dividerCursorEditor)
            && dividerCursorEditor.string == "上\n---\n下"
        dividerCursorEditor.setSelectedRange(NSRange(location: 3, length: 0))
        let ordinaryBackspaceIgnored = !RichTextFormatting.handleDividerBackspace(in: dividerCursorEditor)
        let dividerCursor = clickedDivider && backIntoDivider && rightFromDivider && plainLineUntouched
            && typingDividerUntouched && backspaceBelow && backspaceAtDivider && ordinaryBackspaceIgnored
        print("dividerCursor click=\(clickedDivider) back=\(backIntoDivider) right=\(rightFromDivider) plain=\(plainLineUntouched) typing=\(typingDividerUntouched) backspaceBelow=\(backspaceBelow) backspaceAt=\(backspaceAtDivider) ordinary=\(ordinaryBackspaceIgnored)")

        // List markers: the space after a marker is a gap the cursor skips; pasted markers
        // are dropped where they would show up mid-line.
        let markerLengths = ListMarker.length(in: "☐ 买", atParagraphStart: 0) == 2
            && ListMarker.length(in: "• 项", atParagraphStart: 0) == 2
            && ListMarker.length(in: "12. 项", atParagraphStart: 0) == 4
            && ListMarker.length(in: "1.项", atParagraphStart: 0) == nil
            && ListMarker.length(in: "普通", atParagraphStart: 0) == nil
            && ListMarker.isMarkerSpace(in: "• 项", at: 1)
            && !ListMarker.isMarkerSpace(in: "普 通", at: 1)
        let markerCursorEditor = NSTextView()
        markerCursorEditor.isRichText = true
        markerCursorEditor.string = "上\n☐ 买\n1. 二"
        func skipped(_ location: Int, from old: Int, userMove: Bool = true) -> Int {
            RichTextFormatting.selectionAvoidingListMarkers(
                NSRange(location: location, length: 0),
                from: NSRange(location: old, length: 0),
                isUserMove: userMove,
                in: markerCursorEditor
            ).location
        }
        // ⇧⌘← from the end of "☐ 买" selects the marker too, so one Delete clears the line;
        // a selection that starts between the marker and its text grows to take the marker.
        let lineSelection = RichTextFormatting.selectionAvoidingListMarkers(
            NSRange(location: 2, length: 3), from: NSRange(location: 5, length: 0), isUserMove: true, in: markerCursorEditor
        ) == NSRange(location: 2, length: 3)
        let partialMarkerSelection = RichTextFormatting.selectionAvoidingListMarkers(
            NSRange(location: 3, length: 2), from: NSRange(location: 5, length: 0), isUserMove: true, in: markerCursorEditor
        ) == NSRange(location: 2, length: 3)
        let markerCursor = lineSelection && partialMarkerSelection && skipped(3, from: 0) == 4 && skipped(2, from: 0) == 4
            && skipped(3, from: 4) == 1 && skipped(7, from: 0) == 9
            && skipped(4, from: 0) == 4 && skipped(3, from: 0, userMove: false) == 3
        func pasted(_ text: String, into existing: String, at location: Int) -> String {
            let editor = NSTextView()
            editor.isRichText = true
            editor.string = existing
            editor.setSelectedRange(NSRange(location: location, length: 0))
            return RichTextFormatting.textForPaste(text, in: editor)
        }
        let pasteMarkers = pasted("☐ 随便记", into: "☐ ", at: 2) == "随便记"
            && pasted("☐ 随便记", into: "文字", at: 2) == "随便记"
            && pasted("• 项目", into: "• ", at: 2) == "项目"
            && pasted("1. 一", into: "文字", at: 2) == "1. 一"
            && pasted("☐ 随便记", into: "", at: 0) == "☐ 随便记"
            && pasted("☐ 随便记", into: "文字\n", at: 3) == "☐ 随便记"
        let listMarkers = markerLengths && markerCursor && pasteMarkers
        print("listMarkers lengths=\(markerLengths) cursor=\(markerCursor) paste=\(pasteMarkers)")

        // Return on the empty last line below a to-do (its marker just removed, or the list
        // just ended) adds a plain line, not a new to-do.
        let afterTodoEditor = NSTextView()
        afterTodoEditor.isRichText = true
        afterTodoEditor.string = "☐ 买牛奶\n☐ "
        afterTodoEditor.setSelectedRange(NSRange(location: afterTodoEditor.string.utf16.count, length: 0))
        let markerRemoved = RichTextFormatting.handleMarkerBackspace(in: afterTodoEditor)
            && afterTodoEditor.string == "☐ 买牛奶\n"
        let plainAfterBackspace = !RichTextFormatting.handleStructuredNewline(in: afterTodoEditor)
            && afterTodoEditor.string == "☐ 买牛奶\n"
        afterTodoEditor.string = "☐ 买牛奶\n☐ "
        afterTodoEditor.setSelectedRange(NSRange(location: afterTodoEditor.string.utf16.count, length: 0))
        let listEnded = RichTextFormatting.handleStructuredNewline(in: afterTodoEditor)
            && afterTodoEditor.string == "☐ 买牛奶\n"
        let plainAfterListEnd = !RichTextFormatting.handleStructuredNewline(in: afterTodoEditor)
            && afterTodoEditor.string == "☐ 买牛奶\n"
        let plainLineAfterList = markerRemoved && plainAfterBackspace && listEnded && plainAfterListEnd
        print("plainLineAfterList backspace=\(markerRemoved && plainAfterBackspace) listEnd=\(listEnded && plainAfterListEnd)")

        let codeBlocks = plainLineAfterList && listMarkers && dividerCursor && codeButton && trailingLinePlain && fenceStarted && codeKeepsMarkdown && codeContinues && codeEnds && codeRoundTrip && codeBackspace && pastedCode
        print("codeBlock start=\(fenceStarted) keepsMarkdown=\(codeKeepsMarkdown) continues=\(codeContinues) ends=\(codeEnds) roundTrip=\(codeRoundTrip) backspace=\(codeBackspace) pasted=\(pastedCode)")

        print("bold=\(boldSurvived) legacyStrike=\(strikeSurvived) todo=\(todoPending && todoCompleted && todoRemoved && todoSurvived && todoSelectionPreserved && completedTodoNewline && splitCompletedTodo) bullet=\(bulletSurvived) futureBold=\(futureBoldOn && futureBoldOff) bulletToggle=\(bulletsOn && bulletsOff && bulletSelectionPreserved && bulletBecameTodo && todoBecameBullet) markdown=\(markdownChanged && markdownBold && markdownBullets && extendedMarkdown && trailingIsRegular) listExit=\(listExitClean) nesting=\(multiLevelOn && multiLevelOff && multiLevelSurvived && orphanPrevented && tieredMarkers && inheritedMarker && normalizedLegacyMarker) markerProportions=\(markerProportionsAreBalanced) bytes=\(data.count)")
        guard boldSurvived, bulletSurvived, strikeSurvived, futureBoldOn, futureBoldOff, todoPending, todoCompleted, todoRemoved, todoSurvived, todoSelectionPreserved, completedTodoNewline, splitCompletedTodo, bulletsOn, bulletsOff, bulletSelectionPreserved, bulletBecameTodo, todoBecameBullet, markdownChanged, markdownBold, markdownBullets, extendedMarkdown, checkboxClicks, trailingIsRegular, listExitClean, multiLevelOn, multiLevelOff, multiLevelSurvived, orphanPrevented, tieredMarkers, inheritedMarker, normalizedLegacyMarker, markerProportionsAreBalanced, codeBlocks else { exit(1) }
    }
}
