import AppKit
import Carbon.HIToolbox

/// Click to record: the next key press with ⌘, ⌥ or ⌃ becomes the shortcut.
/// Esc cancels recording, Delete clears the shortcut.
@MainActor
final class HotKeyRecorderView: NSView {
    var shortcut: HotKeyShortcut? { didSet { needsDisplay = true } }
    var onRecordingChanged: ((Bool) -> Void)?
    var onShortcutChanged: ((HotKeyShortcut?) -> Void)?
    private(set) var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            needsDisplay = true
            onRecordingChanged?(isRecording)
        }
    }

    init(shortcut: HotKeyShortcut?) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel("新建便签快捷键")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 28) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var displayText: String {
        if isRecording { return "输入快捷键" }
        return shortcut?.displayString ?? "无"
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordedKey(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            if event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
                isRecording = true
            } else {
                super.keyDown(with: event)
            }
            return
        }
        handleRecordedKey(event)
    }

    func stopRecording() {
        isRecording = false
    }

    private func handleRecordedKey(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(HotKeyShortcut.supportedModifiers)
        if modifiers.isEmpty {
            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
                return
            case kVK_Delete, kVK_ForwardDelete:
                shortcut = nil
                stopRecording()
                onShortcutChanged?(nil)
                return
            default:
                break
            }
        }
        let candidate = HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValidGlobalShortcut else {
            NSSound.beep()
            return
        }
        shortcut = candidate
        stopRecording()
        onShortcutChanged?(candidate)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording || shortcut == nil ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let text = displayText as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
