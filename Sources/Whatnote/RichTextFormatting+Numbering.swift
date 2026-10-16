import AppKit

/// Numbered lists: numbers such as 3. and 1.2., renumbering and nesting.
@MainActor
extension RichTextFormatting {
    /// Tab and ⇧Tab on numbered items: "2. " becomes "1.1. " under the item above, and back.
    static func adjustOrderedLevel(in textView: NSTextView, starts: [Int], delta: Int) -> Bool {
        guard let storage = textView.textStorage else { return false }
        var changed = false
        var offset = 0
        var firstChanged: Int?
        for originalStart in starts {
            let start = originalStart + offset
            guard start < storage.length, let marker = orderedMarker(in: storage.string, at: start) else { continue }
            let current = marker.components.count - 1
            var requested = min(maximumListLevel, max(0, current + delta))
            if delta > 0 {
                var parentLimit = 0
                if start > 0 {
                    let previous = (storage.string as NSString).paragraphRange(for: NSRange(location: start - 1, length: 0)).location
                    if let above = orderedMarker(in: storage.string, at: previous) { parentLimit = above.components.count }
                }
                requested = min(requested, parentLimit)
            }
            guard requested != current else { continue }
            let components = requested > current
                ? marker.components + [1]
                : Array(marker.components.prefix(requested + 1))
            let replacement = orderedMarkerText(components)
            let range = NSRange(location: start, length: marker.length)
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { continue }
            storage.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            offset += (replacement as NSString).length - marker.length
            firstChanged = firstChanged ?? start
            changed = true
        }
        if let firstChanged { renumberOrderedBlock(around: firstChanged, in: textView) }
        return changed
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

    static func isOrderedList(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        return paragraphStarts(in: storage.string, selection: textView.selectedRange()).first.map {
            orderedMarker(in: storage.string, at: $0) != nil
        } ?? false
    }

    static let orderedMarkerExpression = try? NSRegularExpression(pattern: #"(\d{1,4}(?:\.\d{1,4}){0,7})\. "#)

    /// A numbered-list marker such as "12. ", or "1.2. " for a nested item, starting at `location`.
    /// `number` is the item's own number, the last of `components`.
    static func orderedMarker(
        in string: String,
        at location: Int
    ) -> (number: Int, length: Int, components: [Int])? {
        let nsString = string as NSString
        guard location < nsString.length,
              let expression = orderedMarkerExpression,
              let match = expression.firstMatch(
                  in: string,
                  options: .anchored,
                  range: NSRange(location: location, length: nsString.length - location)
              ) else { return nil }
        let components = nsString.substring(with: match.range(at: 1)).split(separator: ".").compactMap { Int($0) }
        guard let number = components.last else { return nil }
        return (number, match.range.length, components)
    }

    static func orderedMarkerText(_ components: [Int]) -> String {
        components.map(String.init).joined(separator: ".") + ". "
    }

    /// Renumbers the run of numbered items around `location`: "1. ", "2. ", with nested items
    /// "2.1. ", "2.1.1. " and so on, each indented by its depth. The first item keeps its number.
    static func renumberOrderedBlock(around location: Int, in textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        var string = storage.string as NSString
        var cursor = string.paragraphRange(for: NSRange(location: min(location, string.length - 1), length: 0)).location
        guard orderedMarker(in: storage.string, at: cursor) != nil else { return }
        while cursor > 0 {
            let previous = string.paragraphRange(for: NSRange(location: cursor - 1, length: 0)).location
            guard orderedMarker(in: storage.string, at: previous) != nil else { break }
            cursor = previous
        }
        var items: [(start: Int, length: Int, components: [Int])] = []
        var counters: [Int] = []
        while cursor < string.length, let marker = orderedMarker(in: storage.string, at: cursor) {
            let level = min(marker.components.count - 1, counters.count)
            if counters.isEmpty {
                counters = Array(marker.components.prefix(level + 1))
                while counters.count < level + 1 { counters.append(1) }
            } else if level < counters.count {
                counters = Array(counters.prefix(level + 1))
                counters[level] += 1
            } else {
                counters.append(1)
            }
            items.append((cursor, marker.length, counters))
            cursor = NSMaxRange(string.paragraphRange(for: NSRange(location: cursor, length: 0)))
        }
        let selection = textView.selectedRange()
        var newLocation = selection.location
        var newLength = selection.length
        for item in items.reversed() {
            let style = (storage.attribute(.paragraphStyle, at: item.start, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            let indent = CGFloat(item.components.count - 1) * listIndentStep
            let replacement = orderedMarkerText(item.components)
            let markerRange = NSRange(location: item.start, length: item.length)
            let sameText = string.substring(with: markerRange) == replacement
            if !sameText {
                guard textView.shouldChangeText(in: markerRange, replacementString: replacement) else { return }
                storage.replaceCharacters(in: markerRange, with: replacement)
                textView.didChangeText()
                adjustSelection(
                    location: &newLocation, length: &newLength, changeAt: item.start,
                    delta: (replacement as NSString).length - item.length
                )
            }
            if style.firstLineHeadIndent != indent || style.headIndent != indent {
                let updated = (storage.string as NSString).paragraphRange(for: NSRange(location: item.start, length: 0))
                guard textView.shouldChangeText(in: updated, replacementString: nil) else { return }
                style.firstLineHeadIndent = indent
                style.headIndent = indent
                storage.addAttribute(.paragraphStyle, value: style, range: updated)
                textView.didChangeText()
            }
            string = storage.string as NSString
        }
        textView.setSelectedRange(NSRange(
            location: min(newLocation, storage.length),
            length: min(newLength, max(0, storage.length - newLocation))
        ))
    }
}
