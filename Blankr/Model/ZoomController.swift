import AppKit
import Combine

/// The two zoom levels, and the one place every way of zooming goes through: the View menu,
/// ⌘+ / ⌘- / ⌘0 (with or without Shift, main keyboard or keypad), trackpad pinch and the
/// buttons in the side panel.
///
/// - `uiScale` enlarges the whole app (tabs, panel and notes) on top of the display default.
/// - `readingZoom` sizes only the text of Markdown and code tabs, so a dense file can be shrunk
///   to fit (or enlarged to read) without the chrome changing.
///
/// Zooming acts on whatever is showing: a Markdown or code tab changes its text size,
/// a note changes the app's zoom (as before).
final class ZoomController: ObservableObject {
    static let shared = ZoomController()

    static let uiScaleRange: ClosedRange<Double> = 0.5...2.5
    static let readingZoomRange: ClosedRange<Double> = 0.5...3.0
    private static let step = 0.1

    /// Relative to the display's comfortable default (1.0 = 100%).
    @Published var uiScale: Double {
        didSet { UserDefaults.standard.set(uiScale, forKey: Self.uiScaleKey) }
    }

    /// Text size of Markdown and code tabs (1.0 = 100%). Shared by every such tab.
    @Published var readingZoom: Double {
        didSet { UserDefaults.standard.set(readingZoom, forKey: Self.readingZoomKey) }
    }

    private static let uiScaleKey = "uiScale"
    private static let readingZoomKey = "readingZoom"

    private var keyMonitor: Any?
    private var pinchMonitor: Any?

    private init() {
        let defaults = UserDefaults.standard
        uiScale = Self.clamp(defaults.object(forKey: Self.uiScaleKey) as? Double ?? 1, to: Self.uiScaleRange)
        readingZoom = Self.clamp(defaults.object(forKey: Self.readingZoomKey) as? Double ?? 1, to: Self.readingZoomRange)
    }

    /// True when zooming acts on reading text (a Markdown or code tab is showing).
    var targetsReadingText: Bool {
        NoteSession.shared.activeKind.isViewer
    }

    /// The zoom that ⌘+ / ⌘- currently change, as a percentage.
    var currentPercent: Int {
        Int(((targetsReadingText ? readingZoom : uiScale) * 100).rounded())
    }

    // MARK: - Steps

    func zoomIn() { stepZoom(by: Self.step) }
    func zoomOut() { stepZoom(by: -Self.step) }

    func resetZoom() {
        if targetsReadingText { readingZoom = 1 } else { uiScale = 1 }
    }

    var canZoomIn: Bool {
        targetsReadingText ? readingZoom < Self.readingZoomRange.upperBound : uiScale < Self.uiScaleRange.upperBound
    }

    var canZoomOut: Bool {
        targetsReadingText ? readingZoom > Self.readingZoomRange.lowerBound : uiScale > Self.uiScaleRange.lowerBound
    }

    private func stepZoom(by delta: Double) {
        // Land on whole tens, so a pinch to 87% followed by ⌘+ goes to 90%, not 97%.
        func next(_ value: Double) -> Double {
            let steps = (value / Self.step)
            let target = delta > 0 ? (steps + 0.001).rounded(.down) + 1 : (steps - 0.001).rounded(.up) - 1
            return (target * Self.step * 100).rounded() / 100
        }
        if targetsReadingText {
            readingZoom = Self.clamp(next(readingZoom), to: Self.readingZoomRange)
        } else {
            uiScale = Self.clamp(next(uiScale), to: Self.uiScaleRange)
        }
    }

    // MARK: - Pinch

    /// Applies one step of a trackpad pinch (`magnification` is the event's relative change).
    func pinch(by magnification: CGFloat, ended: Bool) {
        let factor = Double(1 + magnification)
        if targetsReadingText {
            readingZoom = Self.settle(readingZoom * factor, in: Self.readingZoomRange, ended: ended)
        } else {
            uiScale = Self.settle(uiScale * factor, in: Self.uiScaleRange, ended: ended)
        }
    }

    /// Smooth while the fingers move; on release, snap to a round 5% if it's close to one.
    private static func settle(_ value: Double, in range: ClosedRange<Double>, ended: Bool) -> Double {
        var v = (value * 1000).rounded() / 1000
        if ended {
            let snapped = (v * 20).rounded() / 20
            if abs(snapped - v) < 0.02 { v = snapped }
        }
        return clamp(v, to: range)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    // MARK: - Keyboard and trackpad

    /// Catches zoom keys and pinches before any view sees them. The menu's own key equivalents
    /// only match ⌘= exactly, so ⌘+ (Shift) and the keypad keys never zoomed; and pinches would
    /// otherwise be swallowed by the text view or the Markdown web view.
    func installEventMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handlesKey(event) else { return event }
            return nil
        }
        pinchMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, Self.isInMainWindow(event) else { return event }
            self.pinch(by: event.magnification, ended: event.phase == .ended || event.phase == .cancelled)
            return nil
        }
    }

    enum KeyAction: Equatable { case zoomIn, zoomOut, reset }

    /// Which zoom action a key press means, if any: ⌘ with = or +, - or _, 0, on either keyboard.
    static func action(for event: NSEvent) -> KeyAction? {
        guard event.type == .keyDown else { return nil }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods == .command else { return nil }
        switch event.keyCode {
        case 69: return .zoomIn    // keypad +
        case 78: return .zoomOut   // keypad -
        case 82: return .reset     // keypad 0
        default: break
        }
        switch event.charactersIgnoringModifiers {
        case "=", "+": return .zoomIn
        case "-", "_", "\u{2212}": return .zoomOut
        case "0": return .reset
        default: return nil
        }
    }

    private func handlesKey(_ event: NSEvent) -> Bool {
        guard Self.isInMainWindow(event), let action = Self.action(for: event) else { return false }
        switch action {
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .reset: resetZoom()
        }
        return true
    }

    /// Only the editor window zooms; sheets, alerts, popovers and panels keep their keys.
    private static func isInMainWindow(_ event: NSEvent) -> Bool {
        // Gestures go to the window under the pointer; fall back to finding it if AppKit didn't say.
        let underPointer = event.type == .magnify
            ? NSApp.window(withWindowNumber: NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0))
            : nil
        guard NSApp.modalWindow == nil, let window = event.window ?? underPointer, window.sheets.isEmpty else { return false }
        return window === NoteSession.shared.textView?.window
    }
}
