import SwiftUI

@main
struct BlankrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isDarkMode") private var isDarkMode = true
    @ObservedObject private var zoom = ZoomController.shared

    /// Sends a find-bar action to the focused text view (the menu item's tag carries the action).
    private static func find(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender)
    }

    var body: some Scene {
        // One window: every tab lives in a single shared session, and a WindowGroup would
        // spawn an extra (stale) window each time a file is opened from Finder.
        Window("Blankr.", id: "main") {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
                .background(WindowAccessor())
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .defaultSize(width: 760, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NoteSession.shared.addTab()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Open…") {
                    NoteSession.shared.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(after: .pasteboard) {
                Divider()
                Menu("Find") {
                    Button("Find…") { Self.find(.showFindInterface) }
                        .keyboardShortcut("f", modifiers: [.command])
                    Button("Find and Replace…") { Self.find(.showReplaceInterface) }
                        .keyboardShortcut("f", modifiers: [.command, .option])
                    Button("Find Next") { Self.find(.nextMatch) }
                        .keyboardShortcut("g", modifiers: [.command])
                    Button("Find Previous") { Self.find(.previousMatch) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                    Button("Use Selection for Find") { Self.find(.setSearchString) }
                        .keyboardShortcut("e", modifiers: [.command])
                }
            }

            // Join the system View menu rather than adding a second one beside it.
            CommandGroup(before: .toolbar) {
                // Shown for discoverability; the keys themselves (⌘+ and ⌘= alike, keypad
                // too) and trackpad pinches are handled by ZoomController's event monitors.
                Button("Zoom In") { zoom.zoomIn() }
                    .keyboardShortcut("+", modifiers: [.command])

                Button("Zoom Out") { zoom.zoomOut() }
                    .keyboardShortcut("-", modifiers: [.command])

                Button("Actual Size") { zoom.resetZoom() }
                    .keyboardShortcut("0", modifiers: [.command])

                Divider()

                Button("Toggle Line Numbers") {
                    NoteSession.shared.showLineNumbers.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()
            }
        }
    }
}
