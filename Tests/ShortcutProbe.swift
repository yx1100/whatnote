import AppKit

@main
struct ShortcutProbe {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let editor = StickyTextView()
        var boldCount = 0
        var bulletCount = 0
        var todoCount = 0
        var linkCount = 0
        var orderedCount = 0
        var italicCount = 0
        var checkedCount = 0
        var indentationDeltas: [Int] = []
        editor.onToggleBold = { boldCount += 1 }
        editor.onToggleBulletList = { bulletCount += 1 }
        editor.onToggleTodo = { todoCount += 1 }
        editor.onEditLink = { linkCount += 1 }
        editor.onToggleOrderedList = { orderedCount += 1 }
        editor.onToggleItalic = { italicCount += 1 }
        editor.onToggleChecked = { checkedCount += 1 }
        var closeCount = 0
        editor.onCloseNote = { closeCount += 1 }
        editor.onAdjustBulletLevel = { delta in
            indentationDeltas.append(delta)
            return true
        }

        let plainAsterisk = keyEvent(modifiers: [.shift], characters: "*", ignoringModifiers: "*")
        _ = editor.performKeyEquivalent(with: plainAsterisk)
        let markdownAsteriskPassedThrough = bulletCount == 0

        let bold = keyEvent(modifiers: [.command], characters: "b", ignoringModifiers: "b")
        _ = editor.performKeyEquivalent(with: bold)

        // ⌘7 bulleted, ⌘8 numbered, ⌘9 checklist, ⇧⌘U mark as checked, ⌘I italic.
        let bullet = keyEvent(modifiers: [.command], characters: "7", ignoringModifiers: "7")
        _ = editor.performKeyEquivalent(with: bullet)

        let todo = keyEvent(modifiers: [.command], characters: "9", ignoringModifiers: "9")
        _ = editor.performKeyEquivalent(with: todo)

        let checked = keyEvent(modifiers: [.command, .shift], characters: "U", ignoringModifiers: "U")
        _ = editor.performKeyEquivalent(with: checked)

        let italic = keyEvent(modifiers: [.command], characters: "i", ignoringModifiers: "i")
        _ = editor.performKeyEquivalent(with: italic)

        // The former ⇧⌘7 and ⇧⌘L no longer do anything.
        _ = editor.performKeyEquivalent(with: keyEvent(modifiers: [.command, .shift], characters: "&", ignoringModifiers: "&"))
        _ = editor.performKeyEquivalent(with: keyEvent(modifiers: [.command, .shift], characters: "L", ignoringModifiers: "L"))
        let oldTodo = keyEvent(modifiers: [.command, .shift], characters: "X", ignoringModifiers: "X")
        _ = editor.performKeyEquivalent(with: oldTodo)

        let link = keyEvent(modifiers: [.command], characters: "k", ignoringModifiers: "k")
        _ = editor.performKeyEquivalent(with: link)

        let ordered = keyEvent(modifiers: [.command], characters: "8", ignoringModifiers: "8")
        _ = editor.performKeyEquivalent(with: ordered)

        editor.insertTab(nil)
        editor.insertBacktab(nil)

        // ⌘W closes the note; so does Esc pressed twice in quick succession, but not a lone Esc.
        let close = keyEvent(modifiers: [.command], characters: "w", ignoringModifiers: "w")
        _ = editor.performKeyEquivalent(with: close)
        let commandWCloses = closeCount == 1
        editor.keyDown(with: keyEvent(modifiers: [], characters: "\u{1B}", ignoringModifiers: "\u{1B}", keyCode: 53, timestamp: 10))
        let singleEscapeWaits = closeCount == 1
        editor.keyDown(with: keyEvent(modifiers: [], characters: "\u{1B}", ignoringModifiers: "\u{1B}", keyCode: 53, timestamp: 10.2))
        let doubleEscapeCloses = closeCount == 2
        editor.keyDown(with: keyEvent(modifiers: [], characters: "\u{1B}", ignoringModifiers: "\u{1B}", keyCode: 53, timestamp: 20))
        editor.keyDown(with: keyEvent(modifiers: [], characters: "\u{1B}", ignoringModifiers: "\u{1B}", keyCode: 53, timestamp: 25))
        let slowEscapesIgnored = closeCount == 2
        let closeShortcuts = commandWCloses && singleEscapeWaits && doubleEscapeCloses && slowEscapesIgnored

        let editingShortcuts = [
            StickyEditingShortcut.command(for: [.command], key: "c"),
            StickyEditingShortcut.command(for: [.command], key: "x"),
            StickyEditingShortcut.command(for: [.command], key: "v"),
            StickyEditingShortcut.command(for: [.command], key: "a")
        ]

        print("boldShortcut=\(boldCount == 1) bulletShortcut=\(bulletCount == 1) todoShortcut=\(todoCount == 1) linkShortcut=\(linkCount == 1) markdownAsterisk=\(markdownAsteriskPassedThrough) nestingShortcuts=\(indentationDeltas == [1, -1]) editingShortcuts=\(editingShortcuts == [.copy, .cut, .paste, .selectAll]) closeShortcuts=\(closeShortcuts)")
        guard boldCount == 1,
              bulletCount == 1,
              todoCount == 1,
              linkCount == 1,
              orderedCount == 1,
              italicCount == 1,
              checkedCount == 1,
              markdownAsteriskPassedThrough,
              indentationDeltas == [1, -1],
              editingShortcuts == [.copy, .cut, .paste, .selectAll],
              closeShortcuts else { exit(1) }
    }

    private static func keyEvent(
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        ignoringModifiers: String,
        keyCode: UInt16 = 0,
        timestamp: TimeInterval = 0
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: ignoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
