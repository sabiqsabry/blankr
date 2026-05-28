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
        performSave()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NoteSession.shared.loadFiles(urls: urls)
    }

    @objc private func systemWillPowerOff(_ notification: Notification) {
        performSave()
    }

    private func performSave() {
        let session = NoteSession.shared
        session.flushActiveTabFromTextView()
        AutoSaveManager.saveIfNeeded(
            text: session.currentText,
            openedFileURL: session.activeTabOpenedFileURL()
        )
    }
}
