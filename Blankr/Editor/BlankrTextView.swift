import AppKit

class BlankrTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1 else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if let idx = checkboxIndex(at: point) {
            toggleCheckbox(at: idx)
            return
        }

        super.mouseDown(with: event)
    }

    private func checkboxIndex(at point: NSPoint) -> Int? {
        let idx = characterIndexForInsertion(at: point)
        let nsStr = string as NSString

        for i in [idx, idx - 1] where i >= 0 && i < nsStr.length {
            let char = nsStr.substring(with: NSRange(location: i, length: 1))
            if char == FormattingActions.uncheckedBox || char == FormattingActions.checkedBox {
                return i
            }
        }
        return nil
    }

    private func toggleCheckbox(at index: Int) {
        let nsStr = string as NSString
        let char = nsStr.substring(with: NSRange(location: index, length: 1))
        let replacement = char == FormattingActions.uncheckedBox
            ? FormattingActions.checkedBox
            : FormattingActions.uncheckedBox
        let range = NSRange(location: index, length: 1)
        let attrs = textStorage?.attributes(at: index, effectiveRange: nil) ?? [:]
        let attrStr = NSAttributedString(string: replacement, attributes: attrs)

        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage?.replaceCharacters(in: range, with: attrStr)
            didChangeText()
        }
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }

        if NoteSession.shared.copyPreservesLineBreaks {
            super.copy(sender)
            return
        }

        let str = (string as NSString).substring(with: range)
        let flattened = str
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(flattened, forType: .string)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let str = pb.string(forType: .string) {
            self.insertText(str, replacementRange: self.selectedRange())
        }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }
}
