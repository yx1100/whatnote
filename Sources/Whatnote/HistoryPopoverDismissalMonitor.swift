import AppKit

@MainActor
final class HistoryPopoverDismissalMonitor {
    private let popoverWindow: () -> NSWindow?
    /// Windows that belong to the popover, such as a confirmation bubble shown from it.
    private let relatedWindows: () -> [NSWindow]
    private let onDismiss: () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?

    init(
        popoverWindow: @escaping () -> NSWindow?,
        relatedWindows: @escaping () -> [NSWindow] = { [] },
        onDismiss: @escaping () -> Void
    ) {
        self.popoverWindow = popoverWindow
        self.relatedWindows = relatedWindows
        self.onDismiss = onDismiss
    }

    func start() {
        stop()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            self?.handleLocalMouseDown(in: event.window)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            self?.handleGlobalMouseDown()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleKeyDown(keyCode: event.keyCode, in: event.window) else { return event }
            return nil
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func handleLocalMouseDown(in window: NSWindow?) {
        guard window !== popoverWindow(), !relatedWindows().contains(where: { $0 === window }) else { return }
        onDismiss()
    }

    func handleGlobalMouseDown() {
        onDismiss()
    }

    /// Esc in the popover closes it. Returns whether the key was used.
    func handleKeyDown(keyCode: UInt16, in window: NSWindow?) -> Bool {
        guard keyCode == 53, window != nil, window === popoverWindow() else { return false }
        onDismiss()
        return true
    }
}
