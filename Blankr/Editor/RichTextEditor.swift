import SwiftUI
import AppKit

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var session: NoteSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let original = scrollView.documentView as? NSTextView,
              let container = original.textContainer else {
            return scrollView
        }

        let textView = BlankrTextView(frame: original.frame, textContainer: container)
        scrollView.documentView = textView

        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        textView.font = NSFont.systemFont(ofSize: NoteSession.defaultFontSize)
        textView.textColor = .textColor
        textView.backgroundColor = .clear 
        textView.drawsBackground = false
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(width: 48, height: 40)

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: original.frame.width, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.typingAttributes = NoteSession.defaultAttributes
        textView.delegate = context.coordinator

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        session.attachTextView(textView)
        context.coordinator.lastAppliedTabId = session.selectedTabId

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard session.selectedTabId != context.coordinator.lastAppliedTabId else { return }

        context.coordinator.lastAppliedTabId = session.selectedTabId
        let text = session.activeTabPlainText()
        let attributed = NSAttributedString(string: text, attributes: NoteSession.defaultAttributes)
        textView.textStorage?.setAttributedString(attributed)
        textView.typingAttributes = NoteSession.defaultAttributes
        session.cachedText = text
        session.syncPublishedFromActiveTab()
        session.updateFormattingState()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let session: NoteSession
        var lastAppliedTabId: UUID

        init(session: NoteSession) {
            self.session = session
            self.lastAppliedTabId = session.selectedTabId
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.session.updateFormattingState()
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            session.updateActiveTabText(textView.string)
        }

        // MARK: - Checklist Enter-key handling

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleChecklistNewline(textView: textView)
            }
            return false
        }

        private func handleChecklistNewline(textView: NSTextView) -> Bool {
            let nsString = textView.string as NSString
            guard nsString.length > 0 else { return false }

            let sel = textView.selectedRange()
            let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = nsString.substring(with: lineRange).trimmingCharacters(in: .newlines)

            let uc = FormattingActions.uncheckedBox
            let ch = FormattingActions.checkedBox

            // Empty checkbox line → remove it, stop continuing
            if line == uc || line == ch || line == "\(uc) " || line == "\(ch) " {
                if textView.shouldChangeText(in: lineRange, replacementString: "") {
                    textView.textStorage?.replaceCharacters(in: lineRange, with: "")
                    textView.didChangeText()
                }
                return true
            }

            // Line starts with checkbox → continue list
            if line.hasPrefix("\(uc) ") || line.hasPrefix("\(ch) ") {
                let insertion = "\n\(uc) "
                let attrs = textView.typingAttributes
                let attrStr = NSAttributedString(string: insertion, attributes: attrs)
                if textView.shouldChangeText(in: sel, replacementString: insertion) {
                    textView.textStorage?.replaceCharacters(in: sel, with: attrStr)
                    textView.didChangeText()
                    textView.setSelectedRange(NSRange(location: sel.location + insertion.count, length: 0))
                }
                return true
            }

            return false
        }
    }
}
