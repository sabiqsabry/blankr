import SwiftUI

@main
struct BlankrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("uiScale") private var uiScale = 1.0

    private let minScale = 0.8
    private let maxScale = 2.0
    private let scaleStep = 0.1

    var body: some Scene {
        WindowGroup {
            ContentView(uiScale: uiScale)
                .frame(minWidth: 600, minHeight: 400)
                .background(WindowAccessor())
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandMenu("View") {
                Button("Zoom In") {
                    uiScale = min(maxScale, uiScale + scaleStep)
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Zoom Out") {
                    uiScale = max(minScale, uiScale - scaleStep)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Actual Size") {
                    uiScale = 1.0
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
}
