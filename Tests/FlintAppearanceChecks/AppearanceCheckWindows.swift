import AppKit

/// Keep desktop checks away from the user's displays and keyboard focus.
@MainActor
enum AppearanceCheckWindows {
    static let showsWindows = ProcessInfo.processInfo.environment["FLINT_UI_TESTS_VISIBLE"] == "1"

    static func frame(for rect: NSRect) -> NSRect {
        guard !showsWindows else { return rect }
        let desktop = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        return NSRect(x: desktop.minX - rect.width - 4_096, y: desktop.minY - rect.height - 4_096,
                      width: rect.width, height: rect.height)
    }

    static func show(_ window: NSWindow) {
        if showsWindows {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Installing a content controller can let AppKit reposition a titled window.
        // Move it away again before ordering it, including when rendering previews.
        if NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            window.setFrameOrigin(frame(for: window.frame).origin)
        }
        window.orderBack(nil)
        precondition(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) },
                     "Appearance-check windows must stay offscreen: \(window.frame)")
    }
}

@MainActor
final class AppearanceCheckWindow: NSWindow {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
         backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: AppearanceCheckWindows.frame(for: contentRect), styleMask: styleMask,
                   backing: backing, defer: flag)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        AppearanceCheckWindows.showsWindows ? super.constrainFrameRect(frameRect, to: screen) : frameRect
    }
}
