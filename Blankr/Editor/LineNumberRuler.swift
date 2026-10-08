import AppKit

/// Line numbers beside the code view. Line starts are cached and rebuilt only when the text
/// changes, so scrolling large files stays cheap.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var cacheIsStale = true

    /// Rulers sit outside the magnified clip view, so they follow the zoom themselves.
    var zoom: CGFloat = 1 {
        didSet {
            guard zoom != oldValue else { return }
            invalidateLineNumbers()
        }
    }

    private var fontSize: CGFloat { 10.5 * zoom }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        // Since macOS 14 views don't clip their drawing by default, and the ruler's divider line
        // would run up through the tab bar. Keep it inside the editor area.
        clipsToBounds = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange() {
        invalidateLineNumbers()
    }

    /// Call after replacing the text programmatically (switching tabs).
    func invalidateLineNumbers() {
        cacheIsStale = true
        needsDisplay = true
    }

    private func rebuildCacheIfNeeded() {
        guard cacheIsStale, let string = textView?.string as NSString? else { return }
        var starts = [0]
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosing, _ in
            let next = NSMaxRange(enclosing)
            if next < string.length { starts.append(next) }
        }
        // A trailing newline starts one more (empty) line.
        if string.length > 0, string.character(at: string.length - 1) == 10 {
            starts.append(string.length)
        }
        lineStarts = starts
        cacheIsStale = false

        let digits = max(3, String(starts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: attributes).width
        let width = (CGFloat(digits) * digitWidth + 18 * zoom).rounded(.up)
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
    }

    private var attributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
    }

    private func lineIndex(forCharacter index: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= index { low = mid } else { high = mid - 1 }
        }
        return low
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        rebuildCacheIfNeeded()

        let attrs = attributes
        let inset = textView.textContainerOrigin
        let visible = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let length = (textView.string as NSString).length

        var line = lineIndex(forCharacter: charRange.location)
        while line < lineStarts.count {
            let start = lineStarts[line]
            if start > NSMaxRange(charRange) { break }

            let lineRect: NSRect
            if start >= length {
                lineRect = layoutManager.extraLineFragmentRect
            } else {
                let glyph = layoutManager.glyphIndexForCharacter(at: start)
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let y = convert(NSPoint(x: 0, y: lineRect.minY + inset.y), from: textView).y
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attrs)
            let lineHeight = convert(NSSize(width: 0, height: lineRect.height), from: textView).height
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - 8 * zoom, y: y + (abs(lineHeight) - size.height) / 2),
                withAttributes: attrs
            )
            line += 1
        }
    }
}
