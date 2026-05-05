import AppKit
import Combine

struct EditorTab: Identifiable, Equatable {
    let id: UUID
    var customTitle: String?
    var cachedText: String
    var openedFileURL: URL?

    init(
        id: UUID = UUID(),
        customTitle: String? = nil,
        cachedText: String = "",
        openedFileURL: URL? = nil
    ) {
        self.id = id
        self.customTitle = customTitle
        self.cachedText = cachedText
        self.openedFileURL = openedFileURL
    }
}

class NoteSession: ObservableObject {
    static let shared = NoteSession()

    static let defaultFontSize: CGFloat = 11

    @Published var tabs: [EditorTab]
    @Published var selectedTabId: UUID

    @Published var openedFileURL: URL?
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    @Published var fontSize: CGFloat = NoteSession.defaultFontSize
    @Published var alignment: NSTextAlignment = .left
    @Published var isOnChecklistLine = false

    @Published var copyPreservesLineBreaks: Bool = NoteSession.loadCopyPreservesLineBreaksDefault() {
        didSet {
            UserDefaults.standard.set(copyPreservesLineBreaks, forKey: NoteSession.copyLineBreaksKey)
        }
    }

    weak var textView: NSTextView?
    var cachedText: String = ""

    private static let copyLineBreaksKey = "copyPreservesLineBreaks"

    private static func loadCopyPreservesLineBreaksDefault() -> Bool {
        if UserDefaults.standard.object(forKey: copyLineBreaksKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: copyLineBreaksKey)
    }

    private init() {
        let first = EditorTab()
        tabs = [first]
        selectedTabId = first.id
        openedFileURL = nil
        cachedText = ""
    }

    private var activeTabIndex: Int? {
        tabs.firstIndex(where: { $0.id == selectedTabId })
    }

    func title(for tab: EditorTab) -> String {
        if let t = tab.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
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

    func flushActiveTabFromTextView() {
        guard let tv = textView, let idx = activeTabIndex else { return }
        var copy = tabs
        copy[idx].cachedText = tv.string
        tabs = copy
        cachedText = tv.string
    }

    func updateActiveTabText(_ text: String) {
        guard let idx = activeTabIndex else { return }
        var copy = tabs
        copy[idx].cachedText = text
        tabs = copy
        cachedText = text
    }

    func syncPublishedFromActiveTab() {
        guard let idx = activeTabIndex else { return }
        openedFileURL = tabs[idx].openedFileURL
        cachedText = tabs[idx].cachedText
    }

    func activeTabPlainText() -> String {
        if let idx = activeTabIndex {
            return tabs[idx].cachedText
        }
        return cachedText
    }

    func activeTabOpenedFileURL() -> URL? {
        activeTabIndex.map { tabs[$0].openedFileURL } ?? openedFileURL
    }

    func attachTextView(_ textView: NSTextView) {
        self.textView = textView
        let text = activeTabPlainText()
        let attributed = NSAttributedString(string: text, attributes: Self.defaultAttributes)
        textView.textStorage?.setAttributedString(attributed)
        textView.typingAttributes = Self.defaultAttributes
        cachedText = text
    }

    func selectTab(id: UUID) {
        guard id != selectedTabId else { return }
        flushActiveTabFromTextView()
        selectedTabId = id
        syncPublishedFromActiveTab()
    }

    func addTab() {
        flushActiveTabFromTextView()
        let newTab = EditorTab()
        tabs = tabs + [newTab]
        selectedTabId = newTab.id
        syncPublishedFromActiveTab()
    }

    func closeTab(id: UUID) {
        flushActiveTabFromTextView()
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[idx]
        AutoSaveManager.saveIfNeeded(text: tab.cachedText, openedFileURL: tab.openedFileURL)

        let wasSelected = id == selectedTabId
        var nextTabs = tabs
        nextTabs.remove(at: idx)

        if nextTabs.isEmpty {
            let fresh = EditorTab()
            tabs = [fresh]
            selectedTabId = fresh.id
        } else {
            tabs = nextTabs
            if wasSelected {
                let newIndex = idx > 0 ? idx - 1 : 0
                selectedTabId = tabs[newIndex].id
            }
        }
        syncPublishedFromActiveTab()
    }

    func loadFile(url: URL) {
        flushActiveTabFromTextView()
        guard let idx = activeTabIndex else { return }
        AutoSaveManager.saveIfNeeded(text: tabs[idx].cachedText, openedFileURL: tabs[idx].openedFileURL)

        do {
            let data = try Data(contentsOf: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            var copy = tabs
            copy[idx].openedFileURL = url
            copy[idx].cachedText = content
            tabs = copy
            openedFileURL = url
            cachedText = content
            if let textView = textView {
                let attributed = NSAttributedString(string: content, attributes: Self.defaultAttributes)
                textView.textStorage?.setAttributedString(attributed)
                textView.typingAttributes = Self.defaultAttributes
                textView.window?.makeFirstResponder(textView)
            }
            updateFormattingState()
        } catch {}
    }

    func newNote() {
        addTab()
    }

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
        } else {
            isOnChecklistLine = false
        }
    }

    func refocus() {
        textView?.window?.makeFirstResponder(textView)
    }

    var currentText: String {
        textView?.string ?? activeTabPlainText()
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
