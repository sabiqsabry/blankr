import SwiftUI
import AppKit

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var session: NoteSession
    /// App-wide zoom. Applied as scroll-view magnification so text is re-rendered sharp
    /// at every scale instead of being a stretched bitmap.
    let zoom: CGFloat

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

        // Nothing in the editor (line-number gutter included) may draw outside it.
        scrollView.clipsToBounds = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        scrollView.allowsMagnification = false
        scrollView.magnification = zoom

        session.attachTextView(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if scrollView.magnification != zoom {
            // Zoom around the top-left of what's visible, so the text you're reading stays put.
            scrollView.setMagnification(zoom, centeredAt: scrollView.documentVisibleRect.origin)
        }
        (scrollView.verticalRulerView as? LineNumberRuler)?.zoom = zoom
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let session: NoteSession

        init(session: NoteSession) {
            self.session = session
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.session.updateFormattingState()
            }
        }

        func textDidChange(_ notification: Notification) {
            session.markActiveTabEdited()
        }

        // MARK: - Checklist Enter-key handling

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if (textView as? BlankrTextView)?.documentKind.isViewer == true {
                    return handleIndentedNewline(textView: textView)
                }
                return handleChecklistNewline(textView: textView)
            }
            return false
        }

        /// In code, a new line starts at the same indentation as the current one.
        private func handleIndentedNewline(textView: NSTextView) -> Bool {
            let nsString = textView.string as NSString
            let sel = textView.selectedRange()
            let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = nsString.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            textView.insertText("\n" + indent, replacementRange: sel)
            return true
        }

        private func handleChecklistNewline(textView: NSTextView) -> Bool {
            let nsString = textView.string as NSString
            guard nsString.length > 0 else { return false }

            let sel = textView.selectedRange()
            let lineRange = nsString.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = nsString.substring(with: lineRange).trimmingCharacters(in: .newlines)

            // Numbered list: Enter continues with the next number; Enter on an empty item ends the list.
            if let prefix = FormattingActions.numberedPrefix(of: line) {
                let rest = (line as NSString).substring(from: prefix.length).trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    let indentLength = (prefix.indent as NSString).length
                    let range = NSRange(location: lineRange.location + indentLength, length: prefix.length - indentLength)
                    if textView.shouldChangeText(in: range, replacementString: "") {
                        textView.textStorage?.replaceCharacters(in: range, with: "")
                        textView.didChangeText()
                    }
                    return true
                }
                let insertion = "\n\(prefix.indent)\(prefix.number + 1). "
                textView.insertText(insertion, replacementRange: sel)
                return true
            }

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
