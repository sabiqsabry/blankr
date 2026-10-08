import AppKit
import Combine

/// Picks a comfortable base zoom for whichever display the window is on, and keeps the
/// window sensibly sized when it moves between displays. The user's own zoom (⌘= / ⌘-)
/// multiplies on top of this.
final class DisplayScale: ObservableObject {
    static let shared = DisplayScale()

    /// Base zoom for the current display (1.0 on a typical laptop panel).
    @Published private(set) var factor: CGFloat = 1

    private weak var window: NSWindow?
    private var lastVisibleFrame: NSRect?
    private var pendingAdapt: Timer?
    /// v2: the opening size changed to a square, so apply it once more for existing users.
    private static let didSizeKey = "didSizeWindowForDisplay.v2"

    private init() {}

    func track(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screenChanged), name: NSWindow.didChangeScreenNotification, object: window)
        center.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if let screen = window.screen ?? NSScreen.main {
            if !UserDefaults.standard.bool(forKey: Self.didSizeKey) {
                // First launch: a square sized to the display (75% of its shorter side).
                let visible = screen.visibleFrame
                let side = max(600, (min(visible.width, visible.height) * 0.75).rounded())
                let size = NSSize(width: side, height: side)
                window.setFrame(NSRect(origin: .zero, size: size), display: false)
                window.center()
                UserDefaults.standard.set(true, forKey: Self.didSizeKey)
            }
            lastVisibleFrame = screen.visibleFrame
            factor = Self.comfortableFactor(for: screen)
            fit(window, in: screen)
        }
    }

    // MARK: - Base zoom

    /// How much to enlarge so text looks the same size it would on a laptop at arm's length.
    /// Uses the display's physical size to find points-per-inch, and assumes external
    /// displays sit further away (which makes the same point size look smaller).
    static func comfortableFactor(for screen: NSScreen) -> CGFloat {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return 1 }
        let id = CGDirectDisplayID(number.uint32Value)
        let millimeters = CGDisplayScreenSize(id)
        // Projectors, AirPlay and some adapters report no size: leave it to the user.
        guard millimeters.width > 50 else { return 1 }

        let pointsPerInch = screen.frame.width / (millimeters.width / 25.4)
        let referencePointsPerInch: CGFloat = 123   // e.g. 13" MacBook Air at its default
        let viewingDistance: CGFloat = CGDisplayIsBuiltin(id) != 0 ? 20 : 26   // inches

        let raw = (pointsPerInch / referencePointsPerInch) * (viewingDistance / 20)
        let snapped = (raw * 20).rounded() / 20
        return min(1.6, max(0.85, CGDisplayIsBuiltin(id) != 0 ? max(1, snapped) : snapped))
    }

    // MARK: - Moving between displays

    @objc private func screenChanged() {
        // The screen flips mid-drag; wait for the drag to end before resizing.
        pendingAdapt?.invalidate()
        pendingAdapt = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            timer.invalidate()
            self?.adaptToCurrentScreen(proportionally: true)
        }
    }

    @objc private func screenParametersChanged() {
        // A display was connected, removed, or changed resolution.
        adaptToCurrentScreen(proportionally: false)
    }

    private func adaptToCurrentScreen(proportionally: Bool) {
        guard let window, let screen = window.screen else { return }
        let visible = screen.visibleFrame
        factor = Self.comfortableFactor(for: screen)

        if proportionally, !window.styleMask.contains(.fullScreen), let old = lastVisibleFrame, old != visible {
            // Keep the window the same share of the screen it had on the old display.
            var frame = window.frame
            let width = frame.width * visible.width / old.width
            let height = frame.height * visible.height / old.height
            frame.origin.x += (frame.width - width) / 2
            frame.origin.y += (frame.height - height) / 2
            frame.size = NSSize(width: width, height: height)
            window.setFrame(frame, display: true, animate: true)
        }
        lastVisibleFrame = visible
        fit(window, in: screen)
    }

    /// Never let the window be bigger than, or hang off, the display it is on.
    private func fit(_ window: NSWindow, in screen: NSScreen) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(max(frame.width, window.minSize.width), visible.width)
        frame.size.height = min(max(frame.height, window.minSize.height), visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        if frame != window.frame {
            window.setFrame(frame, display: true, animate: true)
        }
    }
}
