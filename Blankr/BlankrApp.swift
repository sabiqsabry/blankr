import SwiftUI

@main
struct BlankrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
                .background(WindowAccessor())
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .defaultSize(width: 900, height: 650)
    }
}
