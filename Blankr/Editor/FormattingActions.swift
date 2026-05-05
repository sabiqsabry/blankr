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
            storage.addAttribute(.underlineStyle, value: newValue, range: range)
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
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                guard let font = value as? NSFont else { return }
                let newSize = max(8, min(96, font.pointSize + delta))
                storage.addAttribute(.font, value: fm.convert(font, toSize: newSize), range: attrRange)
            }
            storage.endEditing()
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
            storage.beginEditing()
            storage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, attrRange, _ in
                let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? NSMutableParagraphStyle()
                style.alignment = alignment
                storage.addAttribute(.paragraphStyle, value: style, range: attrRange)
            }
            storage.endEditing()
        }

        var attrs = textView.typingAttributes
        let style = ((attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        style.alignment = alignment
        attrs[.paragraphStyle] = style
        textView.typingAttributes = attrs
    }

    // MARK: - Private

    private static func toggleTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        mask: NSFontTraitMask,
        textView: NSTextView
    ) {
        let range = textView.selectedRange()
        let fm = NSFontManager.shared

        if range.length > 0 {
            guard let storage = textView.textStorage else { return }
            storage.beginEditing()
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
            storage.endEditing()
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
