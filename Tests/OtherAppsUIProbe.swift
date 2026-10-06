import AppKit

@main
struct OtherAppsUIProbe {
    @MainActor
    static func main() {
        // A 100×50 image, transparent except a 20×10 block at its bottom-left area
        // (drawn in Quartz's bottom-up coordinates).
        guard let context = CGContext(
            data: nil,
            width: 100,
            height: 50,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { exit(1) }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 10, y: 0, width: 20, height: 10))
        guard let image = context.makeImage() else { exit(2) }

        // Measured from the image's top-left corner, the block sits in the bottom 10 rows.
        guard OtherAppsUI.opaqueBounds(of: image) == CGRect(x: 10, y: 40, width: 20, height: 10) else { exit(3) }

        guard let empty = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage(), OtherAppsUI.opaqueBounds(of: empty) == nil else { exit(4) }

        // Window-server bounds count from the top of the main display; AppKit's from the bottom.
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let converted = OtherAppsUI.appKitFrame(fromWindowServer: CGRect(x: 0, y: 100, width: 40, height: 200))
        guard converted == NSRect(x: 0, y: mainHeight - 300, width: 40, height: 200) else { exit(5) }

        print("other apps' UI: pass")
    }
}
