import AppKit

/// Task lists: the checkbox state of items, checking and unchecking, nesting.
@MainActor
extension RichTextFormatting {
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

    /// Tab and ⇧Tab on checklist items: indent by one step, at most one deeper than the item above.
    static func adjustTodoLevel(in textView: NSTextView, starts: [Int], delta: Int) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let string = storage.string as NSString
        func level(at start: Int) -> Int {
            let style = storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle
            return max(0, Int(round((style?.firstLineHeadIndent ?? 0) / listIndentStep)))
        }
        var changed = false
        for start in starts where start < storage.length && todoState(in: storage.string, at: start) != .plain {
            let current = level(at: start)
            var requested = min(maximumListLevel, max(0, current + delta))
            if delta > 0 {
                var parentLimit = 0
                if start > 0 {
                    let previous = string.paragraphRange(for: NSRange(location: start - 1, length: 0)).location
                    if todoState(in: storage.string, at: previous) != .plain { parentLimit = level(at: previous) + 1 }
                }
                requested = min(requested, parentLimit)
            }
            guard requested != current else { continue }
            let paragraph = string.paragraphRange(for: NSRange(location: start, length: 0))
            guard textView.shouldChangeText(in: paragraph, replacementString: nil) else { continue }
            let style = (storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.firstLineHeadIndent = CGFloat(requested) * listIndentStep
            style.headIndent = CGFloat(requested) * listIndentStep
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            textView.didChangeText()
            changed = true
        }
        if changed {
            var typing = textView.typingAttributes
            if let start = starts.first, start < storage.length {
                typing[.paragraphStyle] = storage.attribute(.paragraphStyle, at: start, effectiveRange: nil)
            }
            textView.typingAttributes = typing
        }
        return changed
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

    static func todoState(in textView: NSTextView) -> TodoState {
        guard let storage = textView.textStorage else { return .plain }
        let start = paragraphStarts(in: storage.string, selection: textView.selectedRange()).first ?? 0
        return todoState(in: storage.string, at: start)
    }

    static func todoState(in string: String, at location: Int) -> TodoState {
        let nsString = string as NSString
        guard location + 2 <= nsString.length,
              nsString.substring(with: NSRange(location: location + 1, length: 1)) == " " else { return .plain }
        switch nsString.substring(with: NSRange(location: location, length: 1)) {
        case pendingTodoMarker: return .pending
        case completedTodoMarker: return .completed
        default: return .plain
        }
    }

    static func applyTodoCompletion(_ completed: Bool, storage: NSTextStorage, paragraphStart: Int) {
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

    static func setTypingTodoCompletion(_ completed: Bool, textView: NSTextView) {
        var typing = textView.typingAttributes
        if completed {
            typing[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            typing.removeValue(forKey: .strikethroughStyle)
        }
        textView.typingAttributes = typing
    }
}
