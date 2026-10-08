import AppKit

enum FormattingActions {
    static let uncheckedBox = "\u{2610}" // ☐
    static let checkedBox   = "\u{2611}" // ☑

    static func insertChecklistItem(textView: NSTextView) {
        let range = textView.selectedRange()
        let nsString = textView.string as NSString

        var prefix = ""
        if range.location > 0 {
            let prev = nsString.substring(with: NSRange(location: range.location - 1, length: 1))
            if prev != "\n" { prefix = "\n" }
        }

        let insertion = prefix + uncheckedBox + " "
        let attrs = textView.typingAttributes
        let attrStr = NSAttributedString(string: insertion, attributes: attrs)

        if textView.shouldChangeText(in: range, replacementString: insertion) {
            textView.textStorage?.replaceCharacters(in: range, with: attrStr)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + insertion.count, length: 0))
        }
    }

    // MARK: - Numbered list

    struct NumberedPrefix {
        let indent: String
        let number: Int
        /// UTF-16 length of indent + "12. ".
        let length: Int
    }

    private static let numberedPattern = try! NSRegularExpression(pattern: #"^([ \t]*)(\d{1,3})\.[ \t]"#)

    /// "12. " at the start of a line (after optional indentation), if present.
    static func numberedPrefix(of line: String) -> NumberedPrefix? {
        let ns = line as NSString
        guard let m = numberedPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let number = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return NumberedPrefix(indent: ns.substring(with: m.range(at: 1)), number: number, length: m.range.length)
    }

    /// Turns the current line into a numbered item (continuing from the line above), or
    /// removes the number if it already has one.
    static func toggleNumberedItem(textView: NSTextView) {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let line = ns.substring(with: lineRange)

        if let existing = numberedPrefix(of: line) {
            let indentLength = (existing.indent as NSString).length
            let range = NSRange(location: lineRange.location + indentLength, length: existing.length - indentLength)
            replace(range, with: "", in: textView)
            let caret = sel.location >= NSMaxRange(range) ? sel.location - range.length : range.location
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            return
        }

        var number = 1
        if lineRange.location > 0 {
            let previous = ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
            if let prefix = numberedPrefix(of: ns.substring(with: previous)) {
                number = prefix.number + 1
            }
        }
        let indentLength = (String(line.prefix { $0 == " " || $0 == "\t" }) as NSString).length
        let insertAt = lineRange.location + indentLength
        let insertion = "\(number). "
        replace(NSRange(location: insertAt, length: 0), with: insertion, in: textView)
        let shift = (insertion as NSString).length
        textView.setSelectedRange(NSRange(location: max(sel.location, insertAt) + shift, length: 0))
    }

    private static func replace(_ range: NSRange, with string: String, in textView: NSTextView) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        let attrs = textView.typingAttributes
        textView.textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: attrs))
        textView.didChangeText()
    }

    static func toggleBold(textView: NSTextView) {
        toggleTrait(.bold, mask: .boldFontMask, textView: textView)
    }

    static func toggleItalic(textView: NSTextView) {
        toggleTrait(.italic, mask: .italicFontMask, textView: textView)
    }

    static func toggleUnderline(textView: NSTextView) {
        let range = textView.selectedRange()
        if range.length > 0 {
            guard let storage = textView.textStorage else { return }
            let current = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            editAttributes(in: range, textView: textView) {
                storage.addAttribute(.underlineStyle, value: newValue, range: range)
            }
        } else {
            var attrs = textView.typingAttributes
            let current = (attrs[.underlineStyle] as? Int) ?? 0
            attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            textView.typingAttributes = attrs
        }
    }

    static func adjustFontSize(by delta: CGFloat, textView: NSTextView) {
        let range = textView.selectedRange()
        let fm = NSFontManager.shared

        if range.length > 0 {
            guard let storage = textView.textStorage else { return }
            editAttributes(in: range, textView: textView) {
                storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    guard let font = value as? NSFont else { return }
                    let newSize = max(8, min(96, font.pointSize + delta))
                    storage.addAttribute(.font, value: fm.convert(font, toSize: newSize), range: attrRange)
                }
            }
        } else {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NoteSession.defaultFontSize)
            let newSize = max(8, min(96, font.pointSize + delta))
            attrs[.font] = fm.convert(font, toSize: newSize)
            textView.typingAttributes = attrs
        }
    }

    static func setAlignment(_ alignment: NSTextAlignment, textView: NSTextView) {
        let range = textView.selectedRange()
        let paragraphRange = (textView.string as NSString).paragraphRange(for: range)

        if let storage = textView.textStorage, paragraphRange.length > 0 {
            editAttributes(in: paragraphRange, textView: textView) {
                storage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, attrRange, _ in
                    let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                        ?? NSMutableParagraphStyle()
                    style.alignment = alignment
                    storage.addAttribute(.paragraphStyle, value: style, range: attrRange)
                }
            }
        }

        var attrs = textView.typingAttributes
        let style = ((attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        style.alignment = alignment
        attrs[.paragraphStyle] = style
        textView.typingAttributes = attrs
    }

    // MARK: - Private

    /// Wraps an attribute-only change so the text view records it for undo and reports it
    /// as an edit (which is what marks the tab as needing a save).
    private static func editAttributes(in range: NSRange, textView: NSTextView, _ change: () -> Void) {
        guard let storage = textView.textStorage,
              textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change()
        storage.endEditing()
        textView.didChangeText()
    }

    private static func toggleTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        mask: NSFontTraitMask,
        textView: NSTextView
    ) {
        let range = textView.selectedRange()
        let fm = NSFontManager.shared

        if range.length > 0 {
            guard let storage = textView.textStorage else { return }
            editAttributes(in: range, textView: textView) {
                storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    guard let font = value as? NSFont else { return }
                    let newFont: NSFont
                    if font.fontDescriptor.symbolicTraits.contains(trait) {
                        newFont = fm.convert(font, toNotHaveTrait: mask)
                    } else {
                        newFont = fm.convert(font, toHaveTrait: mask)
                    }
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
        } else {
            var attrs = textView.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NoteSession.defaultFontSize)
            let newFont: NSFont
            if font.fontDescriptor.symbolicTraits.contains(trait) {
                newFont = fm.convert(font, toNotHaveTrait: mask)
            } else {
                newFont = fm.convert(font, toHaveTrait: mask)
            }
            attrs[.font] = newFont
            textView.typingAttributes = attrs
        }
    }
}
