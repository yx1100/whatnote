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

@MainActor
final class PreferencesViewController: NSViewController {
    /// Applies a shortcut and returns false when macOS rejects it.
    private let applyShortcut: (HotKeyShortcut?) -> Bool
    private let onRecordingChanged: (Bool) -> Void
    private let recorder: HotKeyRecorderView
    private let statusLabel = NSTextField(labelWithString: "")
    private let doubleEscapeCheckbox = NSButton(checkboxWithTitle: "连按两次 Esc 关闭便签", target: nil, action: nil)
    private let commandWCheckbox = NSButton(checkboxWithTitle: "按 ⌘W 关闭便签", target: nil, action: nil)
    private let launchCheckbox = NSButton(checkboxWithTitle: "登录时打开", target: nil, action: nil)
    private let launchHint = NSTextField(labelWithString: "")
    private let openLoginItemsButton = NSButton(title: "打开系统设置", target: nil, action: nil)

    init(
        shortcut: HotKeyShortcut?,
        applyShortcut: @escaping (HotKeyShortcut?) -> Bool,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        self.applyShortcut = applyShortcut
        self.onRecordingChanged = onRecordingChanged
        recorder = HotKeyRecorderView(shortcut: shortcut)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let title = NSTextField(labelWithString: "新建便签")
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.toolTip = "点按后输入新的快捷键。按 Esc 取消，按 Delete 清除。"
        recorder.onRecordingChanged = { [weak self] isRecording in
            self?.onRecordingChanged(isRecording)
        }
        recorder.onShortcutChanged = { [weak self] shortcut in
            self?.commit(shortcut)
        }
        let resetButton = NSButton(title: "还原", target: self, action: #selector(resetToDefault))
        resetButton.bezelStyle = .rounded
        resetButton.toolTip = "还原为 \(HotKeyShortcut.defaultNewNote.displayString)"
        let shortcutRow = NSStackView(views: [title, recorder, resetButton])
        shortcutRow.orientation = .horizontal
        shortcutRow.alignment = .centerY
        shortcutRow.spacing = 10

        for label in [statusLabel, launchHint] {
            label.font = .systemFont(ofSize: 11)
            label.lineBreakMode = .byTruncatingTail
        }
        statusLabel.textColor = .systemRed

        let separator = NSBox()
        separator.boxType = .separator

        let closeTip = "关闭的便签会移到“已完成的便签”"
        doubleEscapeCheckbox.target = self
        doubleEscapeCheckbox.action = #selector(toggleDoubleEscape)
        doubleEscapeCheckbox.toolTip = closeTip
        commandWCheckbox.target = self
        commandWCheckbox.action = #selector(toggleCommandW)
        commandWCheckbox.toolTip = closeTip
        refreshCloseOptions()

        let secondSeparator = NSBox()
        secondSeparator.boxType = .separator

        launchCheckbox.target = self
        launchCheckbox.action = #selector(toggleLaunchAtLogin)
        openLoginItemsButton.target = self
        openLoginItemsButton.action = #selector(openLoginItems)
        openLoginItemsButton.bezelStyle = .rounded
        openLoginItemsButton.controlSize = .small
        let launchRow = NSStackView(views: [launchCheckbox, openLoginItemsButton])
        launchRow.orientation = .horizontal
        launchRow.alignment = .centerY
        launchRow.spacing = 10

        let version = NSTextField(labelWithString: Self.versionText)
        version.font = .systemFont(ofSize: 11)
        version.textColor = .tertiaryLabelColor
        version.isHidden = Self.versionText.isEmpty

        let content = NSStackView(views: [
            shortcutRow, statusLabel, separator,
            doubleEscapeCheckbox, commandWCheckbox, secondSeparator,
            launchRow, launchHint, version
        ])
        content.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        content.setCustomSpacing(14, after: statusLabel)
        content.setCustomSpacing(14, after: separator)
        content.setCustomSpacing(14, after: commandWCheckbox)
        content.setCustomSpacing(14, after: secondSeparator)

        NSLayoutConstraint.activate([
            recorder.widthAnchor.constraint(equalToConstant: 150),
            recorder.heightAnchor.constraint(equalToConstant: 26),
            content.widthAnchor.constraint(equalToConstant: 360),
            separator.widthAnchor.constraint(equalToConstant: 320),
            secondSeparator.widthAnchor.constraint(equalToConstant: 320)
        ])
        view = content
        statusLabel.isHidden = true
        refreshLaunchAtLogin()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // The user may have changed it in System Settings meanwhile.
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin(error: String? = nil) {
        let state = LaunchAtLogin.state
        launchCheckbox.state = state == .enabled || state == .requiresApproval ? .on : .off
        launchCheckbox.isEnabled = state != .unsupported
        openLoginItemsButton.isHidden = state != .requiresApproval

        var hint = ""
        switch state {
        case .unsupported:
            hint = "需要 macOS 13 或更高版本"
        case .requiresApproval:
            hint = "需在系统设置的“登录项”中允许"
        case .enabled, .disabled:
            if !LaunchAtLogin.isInApplicationsFolder { hint = "请先将 App 移到“应用程序”文件夹" }
        }
        if let error { hint = "设置失败：\(error)" }
        launchHint.stringValue = hint
        launchHint.isHidden = hint.isEmpty
        launchHint.textColor = error == nil && state != .requiresApproval ? .secondaryLabelColor : .systemOrange
    }

    @objc private func toggleLaunchAtLogin() {
        let error = LaunchAtLogin.setEnabled(launchCheckbox.state == .on)
        refreshLaunchAtLogin(error: error)
    }

    /// "随便记 1.1", from the app's version; empty when it has none (e.g. in tests).
    static var versionText: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return "" }
        return "随便记 \(version)"
    }

    private func refreshCloseOptions() {
        doubleEscapeCheckbox.state = ClosePreferences.closesOnDoubleEscape() ? .on : .off
        commandWCheckbox.state = ClosePreferences.closesOnCommandW() ? .on : .off
    }

    @objc private func toggleDoubleEscape() {
        UserDefaults.standard.set(doubleEscapeCheckbox.state == .on, forKey: ClosePreferences.doubleEscapeKey)
    }

    @objc private func toggleCommandW() {
        UserDefaults.standard.set(commandWCheckbox.state == .on, forKey: ClosePreferences.commandWKey)
    }

    @objc private func openLoginItems() {
        LaunchAtLogin.openSystemSettings()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        recorder.stopRecording()
    }

    func update(shortcut: HotKeyShortcut?) {
        recorder.shortcut = shortcut
        showError(nil)
        refreshLaunchAtLogin()
    }

    @objc private func resetToDefault() {
        recorder.stopRecording()
        recorder.shortcut = .defaultNewNote
        commit(.defaultNewNote)
    }

    private func commit(_ shortcut: HotKeyShortcut?) {
        if applyShortcut(shortcut) {
            showError(nil)
        } else {
            recorder.shortcut = HotKeyPreferences.newNoteShortcut()
            showError("此快捷键不可用，可能已被其他 App 占用")
        }
    }

    private func showError(_ message: String?) {
        statusLabel.stringValue = message ?? ""
        statusLabel.isHidden = message == nil
    }
}
