import AppKit
import ScreenCaptureKit

/// Other apps' UI on screen, such as the Dock or floating panels, for arranging notes around it.
/// A window's bounds often include transparent margins; with the Screen Recording permission
/// (macOS 14 or later) each window near a screen edge is trimmed to what it actually draws.
@MainActor
enum OtherAppsUI {
    struct Window {
        let id: CGWindowID
        /// Bounds measured from the top of the main display, as the window server reports them.
        let bounds: CGRect
    }

    private static let askedForPermissionKey = "AskedForScreenRecording"

    /// Other apps' on-screen windows whose bounds touch the left, right or bottom edge of `visibleFrame`.
    /// Reading window bounds needs no permission.
    static func edgeWindows(near visibleFrame: NSRect, tolerance: CGFloat = 24) -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info -> Window? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownProcess,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1 >= 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
            let frame = appKitFrame(fromWindowServer: bounds)
            let touchesEdge = frame.minX <= visibleFrame.minX + tolerance
                || frame.maxX >= visibleFrame.maxX - tolerance
                || frame.minY <= visibleFrame.minY + tolerance
            guard touchesEdge, frame.intersects(visibleFrame) else { return nil }
            return Window(id: CGWindowID(number.uint32Value), bounds: bounds)
        }
    }

    /// Where each window shows something, in AppKit screen coordinates. Without the Screen
    /// Recording permission, or before macOS 14, this is the whole window.
    static func visibleFrames(of windows: [Window]) async -> [NSRect] {
        let whole = windows.map { appKitFrame(fromWindowServer: $0.bounds) }
        guard !windows.isEmpty else { return [] }
        guard CGPreflightScreenCaptureAccess() else {
            // Ask once; macOS shows its own prompt and the setting applies after a relaunch.
            if !UserDefaults.standard.bool(forKey: askedForPermissionKey) {
                UserDefaults.standard.set(true, forKey: askedForPermissionKey)
                _ = CGRequestScreenCaptureAccess()
            }
            return whole
        }
        guard #available(macOS 14.0, *),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return whole }
        var frames: [NSRect] = []
        for (window, fallback) in zip(windows, whole) {
            guard let captured = content.windows.first(where: { $0.windowID == window.id }),
                  let drawn = await drawnBounds(of: captured, bounds: window.bounds) else {
                frames.append(fallback)
                continue
            }
            frames.append(appKitFrame(fromWindowServer: drawn))
        }
        return frames
    }

    @available(macOS 14.0, *)
    private static func drawnBounds(of window: SCWindow, bounds: CGRect) async -> CGRect? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(bounds.width * scale))
        configuration.height = max(1, Int(bounds.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
              let opaque = opaqueBounds(of: image) else { return nil }
        let xScale = bounds.width / CGFloat(image.width)
        let yScale = bounds.height / CGFloat(image.height)
        return CGRect(
            x: bounds.minX + opaque.minX * xScale,
            y: bounds.minY + opaque.minY * yScale,
            width: opaque.width * xScale,
            height: opaque.height * yScale
        )
    }

    /// The smallest rectangle holding every pixel that is not (nearly) transparent, in pixels
    /// from the image's top-left corner.
    nonisolated static func opaqueBounds(of image: CGImage, alphaThreshold: UInt8 = 24) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // The bitmap's first row in memory is the top of the image.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > alphaThreshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Converts window-server bounds (from the top of the main display) to AppKit's bottom-up frame.
    nonisolated static func appKitFrame(fromWindowServer rect: CGRect) -> NSRect {
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(x: rect.minX, y: mainDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
