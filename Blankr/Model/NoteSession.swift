import AppKit
import Combine

struct EditorTab: Identifiable {
    let id: UUID
    var customTitle: String?
    /// Full formatted text, so switching tabs never strips bold, size or alignment.
    var content: NSAttributedString
    var fileURL: URL?
    /// Blankr created this file (an auto-saved note), so it may rename it or change its type.
    var ownsFile: Bool
    var isDirty: Bool
    var kind: DocumentKind
    /// Markdown and code open as viewers; this turns on editing (Markdown: shows the source).
    var isEditing: Bool
    var wrapsLines: Bool

    init(
        id: UUID = UUID(),
        customTitle: String? = nil,
        content: NSAttributedString = NSAttributedString(),
        fileURL: URL? = nil,
        ownsFile: Bool = false,
        isDirty: Bool = false,
        kind: DocumentKind = .note,
        isEditing: Bool = false,
        wrapsLines: Bool? = nil
    ) {
        self.id = id
        self.customTitle = customTitle
        self.content = content
        self.fileURL = fileURL
        self.ownsFile = ownsFile
        self.isDirty = isDirty
        self.kind = kind
        self.isEditing = isEditing
        // Prose wraps; code keeps its lines intact and scrolls sideways.
        self.wrapsLines = wrapsLines ?? (kind == .markdown)
    }

    /// A tab for a file read from disk, styled for how it will be shown.
    static func forFile(_ url: URL, content: NSAttributedString, id: UUID = UUID()) -> EditorTab {
        let kind = DocumentKind.detect(url: url, text: content.string)
        let styled = kind.isViewer
            ? NSAttributedString(string: content.string, attributes: CodeTheme.baseAttributes)
            : content
        return EditorTab(id: id, content: styled, fileURL: url, kind: kind)
    }

    var isBlank: Bool {
        content.length == 0 && fileURL == nil && customTitle == nil
    }
}

class NoteSession: ObservableObject {
    static let shared = NoteSession()

    static let defaultFontSize: CGFloat = 11

    @Published var tabs: [EditorTab]
    @Published var selectedTabId: UUID

    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    @Published var fontSize: CGFloat = NoteSession.defaultFontSize
    @Published var alignment: NSTextAlignment = .left
    @Published var isOnChecklistLine = false
    @Published var isOnNumberedLine = false

    /// Line numbers beside every tab's text. Off unless the user turns them on.
    @Published var showLineNumbers: Bool = UserDefaults.standard.bool(forKey: NoteSession.lineNumbersKey) {
        didSet {
            UserDefaults.standard.set(showLineNumbers, forKey: NoteSession.lineNumbersKey)
            applyMode()
        }
    }

    @Published var copyPreservesLineBreaks: Bool = NoteSession.loadCopyPreservesLineBreaksDefault() {
        didSet {
            UserDefaults.standard.set(copyPreservesLineBreaks, forKey: NoteSession.copyLineBreaksKey)
        }
    }

    /// Rendered Markdown for the active tab while it is in preview mode (html is nil while rendering).
    struct Preview: Equatable {
        let tabId: UUID
        var html: String?
        let baseURL: URL?
    }

    @Published private(set) var preview: Preview?
    @Published private(set) var activeLineCount = 0

    weak var textView: NSTextView?
    /// The tab whose content the text view is showing; flushing only trusts the view for this tab.
    private var displayedTabId: UUID?
    private var highlightGeneration = 0

    private static let copyLineBreaksKey = "copyPreservesLineBreaks"
    private static let lineNumbersKey = "showLineNumbers"

    private static func loadCopyPreservesLineBreaksDefault() -> Bool {
        if UserDefaults.standard.object(forKey: copyLineBreaksKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: copyLineBreaksKey)
    }

    private init() {
        if let restored = SessionStore.load(), !restored.tabs.isEmpty {
            tabs = restored.tabs
            selectedTabId = restored.tabs.first(where: { $0.id == restored.selectedTabId })?.id
                ?? restored.tabs[0].id
        } else {
            let first = EditorTab()
            tabs = [first]
            selectedTabId = first.id
        }
    }

    private var activeTabIndex: Int? {
        tabs.firstIndex(where: { $0.id == selectedTabId })
    }

    var activeTab: EditorTab? {
        activeTabIndex.map { tabs[$0] }
    }

    var activeKind: DocumentKind {
        activeTab?.kind ?? .note
    }

    // MARK: - Titles

    func title(for tab: EditorTab) -> String {
        if let t = tab.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        if let url = tab.fileURL {
            // Code and Markdown keep their extension: "main.py" says more than "main".
            return tab.kind.isViewer ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        }
        return "Untitled"
    }

    func updateTabTitleDraft(id: UUID, draft: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        var copy = tabs
        copy[idx].customTitle = draft.isEmpty ? nil : draft
        tabs = copy
    }

    func commitTabTitle(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        var copy = tabs
        if let raw = copy[idx].customTitle {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            copy[idx].customTitle = t.isEmpty ? nil : t
        }
        tabs = copy
    }

    // MARK: - Editor sync

    func attachTextView(_ textView: NSTextView) {
        self.textView = textView
        displayActiveTab()
    }

    func flushActiveTabFromTextView() {
        guard let tv = textView, let storage = tv.textStorage,
              let idx = activeTabIndex, displayedTabId == tabs[idx].id else { return }
        tabs[idx].content = NSAttributedString(attributedString: storage)
    }

    /// Called on every edit; only publishes the first time a tab goes dirty.
    func markActiveTabEdited() {
        guard let idx = activeTabIndex else { return }
        if tabs[idx].kind.isViewer {
            scheduleHighlight(after: 0.25)
        }
        guard !tabs[idx].isDirty else { return }
        tabs[idx].isDirty = true
    }

    private func displayActiveTab() {
        guard let idx = activeTabIndex else { return }
        let tab = tabs[idx]
        activeLineCount = Self.lineCount(of: tab.content.string)
        updatePreview()

        guard let tv = textView, let storage = tv.textStorage else { return }
        (tv as? BlankrTextView)?.configure(kind: tab.kind, editable: !tab.kind.isViewer || tab.isEditing, wraps: tab.wrapsLines, lineNumbers: showLineNumbers)
        storage.setAttributedString(tab.content)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
        if tab.kind.isViewer {
            tv.typingAttributes = CodeTheme.baseAttributes
        } else {
            tv.typingAttributes = tab.content.length > 0
                ? tab.content.attributes(at: 0, effectiveRange: nil)
                : Self.defaultAttributes
        }
        // Undo history belongs to the text that was just swapped out.
        tv.undoManager?.removeAllActions()
        displayedTabId = tab.id
        (tv.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.invalidateLineNumbers()
        if tab.kind.isViewer {
            scheduleHighlight(after: 0)
        }
        updateFormattingState()
        DispatchQueue.main.async { [weak self, weak tv] in
            // Each tab opens at its top, even if layout was still settling (e.g. at launch).
            (tv as? BlankrTextView)?.scrollToStart()
            self?.refocus()
        }
    }

    // MARK: - Viewer modes

    /// Markdown: switch between the rendered preview and editing the source.
    /// Code: switch between read-only and editable.
    func setEditing(_ editing: Bool) {
        guard let idx = activeTabIndex, tabs[idx].kind.isViewer, tabs[idx].isEditing != editing else { return }
        flushActiveTabFromTextView()
        tabs[idx].isEditing = editing
        applyMode()
        if editing { refocus() }
    }

    func setWrapsLines(_ wraps: Bool) {
        guard let idx = activeTabIndex, tabs[idx].wrapsLines != wraps else { return }
        tabs[idx].wrapsLines = wraps
        applyMode()
    }

    /// Re-applies the active tab's mode without reloading its text (keeps selection and undo).
    private func applyMode() {
        guard let idx = activeTabIndex else { return }
        let tab = tabs[idx]
        (textView as? BlankrTextView)?.configure(kind: tab.kind, editable: !tab.kind.isViewer || tab.isEditing, wraps: tab.wrapsLines, lineNumbers: showLineNumbers)
        updatePreview()
    }

    private func updatePreview() {
        guard let tab = activeTab, tab.kind == .markdown, !tab.isEditing else {
            preview = nil
            return
        }
        let source = tab.content.string
        let base = tab.fileURL?.deletingLastPathComponent()
        if preview?.tabId != tab.id {
            preview = Preview(tabId: tab.id, html: nil, baseURL: base)
        }
        SyntaxEngine.shared.renderMarkdown(source) { [weak self] html in
            guard let self, self.preview?.tabId == tab.id else { return }
            self.preview = Preview(tabId: tab.id, html: html, baseURL: base)
        }
    }

    /// Colors the code view. Edits re-run this after a short pause; a newer request (or a
    /// tab switch) supersedes older ones, and stale results are dropped.
    private func scheduleHighlight(after delay: TimeInterval) {
        guard let idx = activeTabIndex, let language = tabs[idx].kind.sourceLanguage,
              let tv = textView, let storage = tv.textStorage else { return }
        highlightGeneration += 1
        let generation = highlightGeneration
        let tabId = tabs[idx].id

        let run = { [weak self, weak tv] in
            guard let self, let tv, generation == self.highlightGeneration else { return }
            let text = storage.string
            self.activeLineCount = Self.lineCount(of: text)
            SyntaxEngine.shared.highlight(text, language: language) { tokens in
                guard generation == self.highlightGeneration, self.displayedTabId == tabId,
                      storage.string == text else { return }
                CodeTheme.apply(tokens, to: storage)
                tv.typingAttributes = CodeTheme.baseAttributes
            }
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
        } else {
            run()
        }
    }

    private static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 1
        for unit in text.utf16 where unit == 10 { count += 1 }
        if text.hasSuffix("\n") { count -= 1 }
        return count
    }

    private func activate(_ id: UUID) {
        selectedTabId = id
        displayActiveTab()
    }

    // MARK: - Tabs

    func selectTab(id: UUID) {
        guard id != selectedTabId else { return }
        flushActiveTabFromTextView()
        activate(id)
    }

    func addTab() {
        flushActiveTabFromTextView()
        let newTab = EditorTab()
        tabs.append(newTab)
        activate(newTab.id)
    }

    func newNote() {
        addTab()
    }

    func closeTab(id: UUID) {
        flushActiveTabFromTextView()
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard saveTab(at: idx) else {
            showSaveError(for: tabs[idx])
            return
        }

        let wasSelected = id == selectedTabId
        tabs.remove(at: idx)

        if tabs.isEmpty {
            let fresh = EditorTab()
            tabs = [fresh]
            activate(fresh.id)
        } else if wasSelected {
            activate(tabs[idx > 0 ? idx - 1 : 0].id)
        }
    }

    /// Opens each file in its own tab. A file that is already open just gets selected,
    /// and an empty untitled tab is reused rather than left behind.
    func openFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        flushActiveTabFromTextView()

        var lastOpened: UUID?
        for url in urls {
            if let existing = tabs.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
                lastOpened = existing.id
                continue
            }
            let content: NSAttributedString
            do {
                content = try DocumentIO.read(url: url)
            } catch {
                showOpenError(for: url)
                continue
            }
            let tab = EditorTab.forFile(url, content: content)
            if let idx = activeTabIndex, tabs[idx].isBlank {
                tabs[idx] = tab
                selectedTabId = tab.id
            } else {
                tabs.append(tab)
            }
            lastOpened = tab.id
        }

        if let lastOpened {
            activate(lastOpened)
        }
    }

    // MARK: - Saving

    /// Saves every tab to disk and records the open tabs so the next launch restores them.
    func saveAllForTermination() {
        flushActiveTabFromTextView()
        for idx in tabs.indices {
            saveTab(at: idx)
        }
        SessionStore.save(tabs: tabs, selectedTabId: selectedTabId)
    }

    /// Cheap crash insurance: snapshot the session without touching the user's files.
    func saveSessionSnapshot() {
        flushActiveTabFromTextView()
        SessionStore.save(tabs: tabs, selectedTabId: selectedTabId)
    }

    /// Writes a tab to disk. Returns false only when a write was needed and failed.
    @discardableResult
    private func saveTab(at idx: Int) -> Bool {
        var tab = tabs[idx]
        let content = tab.content
        guard !content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let formatted = DocumentIO.hasFormatting(content)
        let fm = FileManager.default

        let target: URL
        if let current = tab.fileURL {
            if tab.ownsFile {
                // Blankr named this file, so keep its name in step with the tab's title and
                // switch it to RTF once it carries formatting.
                let base = AutoSaveManager.sanitizedFileName(tab.customTitle)
                    ?? current.deletingPathExtension().lastPathComponent
                let ext = formatted || DocumentIO.isRichText(current) ? "rtf" : "txt"
                target = AutoSaveManager.uniqueURL(
                    in: current.deletingLastPathComponent(),
                    baseName: base,
                    ext: ext,
                    ignoring: current
                )
            } else {
                target = current
            }
            let unchanged = target.standardizedFileURL == current.standardizedFileURL
            if !tab.isDirty && unchanged && fm.fileExists(atPath: current.path) { return true }
        } else {
            guard let desktop = AutoSaveManager.desktopDirectory else { return false }
            target = AutoSaveManager.uniqueURL(
                in: desktop,
                baseName: AutoSaveManager.sanitizedFileName(tab.customTitle) ?? AutoSaveManager.timestampFileName(),
                ext: formatted ? "rtf" : "txt"
            )
            tab.ownsFile = true
        }

        do {
            try DocumentIO.write(content, to: target)
        } catch {
            return false
        }

        if let old = tab.fileURL, old.standardizedFileURL != target.standardizedFileURL {
            try? fm.removeItem(at: old)
        }
        tab.fileURL = target
        tab.isDirty = false
        tabs[idx] = tab
        return true
    }

    /// Attach to the window as a sheet so the message appears where the user is looking.
    private func present(_ alert: NSAlert) {
        if let window = textView?.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showOpenError(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "Blankr. couldn't open \u{201C}\(url.lastPathComponent)\u{201D}."
        alert.informativeText = "Blankr. shows notes, Markdown and code. This file isn't text it can read (it may be an image, archive or other binary file)."
        present(alert)
    }

    private func showSaveError(for tab: EditorTab) {
        let alert = NSAlert()
        alert.messageText = "Blankr. couldn't save \u{201C}\(title(for: tab))\u{201D}."
        alert.informativeText = "The tab was left open so nothing is lost."
        present(alert)
    }

    // MARK: - Formatting state

    func updateFormattingState() {
        guard let textView = textView else { return }

        let attrs: [NSAttributedString.Key: Any]
        let range = textView.selectedRange()

        if range.length > 0,
           let storage = textView.textStorage,
           range.location < storage.length {
            attrs = storage.attributes(at: range.location, effectiveRange: nil)
        } else {
            attrs = textView.typingAttributes
        }

        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
            fontSize = font.pointSize
        }

        isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0

        if let ps = attrs[.paragraphStyle] as? NSParagraphStyle {
            alignment = ps.alignment
        }

        let nsString = textView.string as NSString
        if nsString.length > 0, range.location <= nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: min(range.location, nsString.length - 1), length: 0))
            let line = nsString.substring(with: lineRange)
            isOnChecklistLine = line.hasPrefix(FormattingActions.uncheckedBox)
                || line.hasPrefix(FormattingActions.checkedBox)
            isOnNumberedLine = FormattingActions.numberedPrefix(of: line) != nil
        } else {
            isOnChecklistLine = false
            isOnNumberedLine = false
        }
    }

    func refocus() {
        // In Markdown preview the web view owns the keyboard (scrolling, copying).
        guard preview == nil else { return }
        textView?.window?.makeFirstResponder(textView)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Open notes, Markdown or code"
        if panel.runModal() == .OK {
            openFiles(urls: panel.urls)
        }
    }

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .left
        return [
            .font: NSFont.systemFont(ofSize: defaultFontSize),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: ps
        ]
    }
}
