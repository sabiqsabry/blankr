import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteSession.shared.saveAllForTermination()
    }

    func applicationWillResignActive(_ notification: Notification) {
        NoteSession.shared.saveSessionSnapshot()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NoteSession.shared.openFiles(urls: urls)
    }

    @objc private func systemWillPowerOff(_ notification: Notification) {
        NoteSession.shared.saveAllForTermination()
    }
}
