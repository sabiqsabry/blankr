import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = "Blankr."
            window.toolbar = nil
            window.titleVisibility = .visible
            // The title bar shares the chrome's color, so it and the tab bar read as one surface.
            window.titlebarAppearsTransparent = true
            window.backgroundColor = Chrome.backgroundColor
            DisplayScale.shared.track(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
