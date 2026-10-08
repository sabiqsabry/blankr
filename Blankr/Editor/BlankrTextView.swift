import AppKit

class BlankrTextView: NSTextView {
    private(set) var documentKind: DocumentKind = .note
    private var lineNumbers: LineNumberRuler?
    private var wrapsLines = true
    private var observingClip = false
    private lazy var noteSpellChecking = isContinuousSpellCheckingEnabled

    /// Notes: proportional rich text, wrapped, roomy margins.
    /// Markdown/code: monospaced source, read-only unless editing.
    /// Line numbers are optional for every kind of tab.
    func configure(kind: DocumentKind, editable: Bool, wraps: Bool, lineNumbers showLineNumbers: Bool) {
        _ = noteSpellChecking
        documentKind = kind
        isEditable = editable
        isSelectable = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        let isCode = kind.isViewer
        // With the gutter showing, notes don't need their wide left margin as well.
        textContainerInset = isCode
            ? NSSize(width: 12, height: 14)
            : NSSize(width: showLineNumbers ? 20 : 48, height: 40)
        isContinuousSpellCheckingEnabled = isCode ? false : noteSpellChecking
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = !isCode

        // Gutter first: it takes width from the visible area that wrapping sizes against.
        if let scrollView = enclosingScrollView {
            if showLineNumbers, lineNumbers == nil {
                let ruler = LineNumberRuler(textView: self)
                ruler.zoom = scrollView.magnification
                scrollView.verticalRulerView = ruler
                lineNumbers = ruler
            }
            scrollView.hasVerticalRuler = showLineNumbers
            scrollView.rulersVisible = showLineNumbers
            lineNumbers?.invalidateLineNumbers()
            scrollView.tile()
        }
        setWrapping(isCode ? wraps : true)
    }

    private func setWrapping(_ wraps: Bool) {
        guard let container = textContainer, let scrollView = enclosingScrollView else { return }
        wrapsLines = wraps
        observeClipView(scrollView.contentView)
        let visibleWidth = usableWidth(of: scrollView.contentView)
        if wraps {
            isHorizontallyResizable = false
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: visibleWidth, height: CGFloat.greatestFiniteMagnitude)
            setFrameSize(NSSize(width: visibleWidth, height: frame.height))
            scrollView.hasHorizontalScroller = false
            keepWrappedWidthInSync()
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            isHorizontallyResizable = true
            minSize = NSSize(width: visibleWidth, height: 0)
            setFrameSize(NSSize(width: visibleWidth, height: frame.height))
            sizeToFit()
            scrollView.hasHorizontalScroller = true
            // Only show the bar when a line is actually wider than the view.
            scrollView.autohidesScrollers = true
        }
        autoresizingMask = [.width]
    }

    /// When lines wrap, the text must be exactly as wide as what's visible. Zooming and
    /// resizing can leave it a little wider, which allows a stray sideways scroll that hides
    /// the start of every line, so re-pin the width (and the left edge) whenever the view changes.
    private func observeClipView(_ clip: NSClipView) {
        guard !observingClip else { return }
        observingClip = true
        clip.postsFrameChangedNotifications = true
        clip.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(clipViewChanged), name: NSView.frameDidChangeNotification, object: clip)
        center.addObserver(self, selector: #selector(clipViewChanged), name: NSView.boundsDidChangeNotification, object: clip)
    }

    @objc private func clipViewChanged() {
        guard wrapsLines else { return }
        keepWrappedWidthInSync()
    }

    private func keepWrappedWidthInSync() {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let width = usableWidth(of: clip)
        if abs(frame.width - width) > 0.5 {
            setFrameSize(NSSize(width: width, height: frame.height))
        }
        let leftEdge = startOrigin(of: clip).x
        if abs(clip.bounds.origin.x - leftEdge) > 0.5 {
            clip.scroll(to: NSPoint(x: leftEdge, y: clip.bounds.origin.y))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    /// Visible width for text. The line-number gutter floats over the clip view and is
    /// reported as a content inset, so it has to be subtracted (insets are in document units).
    private func usableWidth(of clip: NSClipView) -> CGFloat {
        clip.bounds.width - clip.contentInsets.left - clip.contentInsets.right
    }

    /// The scroll position that shows the very start of the text. With the gutter visible
    /// this is *not* (0, 0) but (-gutter, 0); AppKit's constraint logic knows the insets.
    private func startOrigin(of clip: NSClipView) -> NSPoint {
        var rect = clip.bounds
        rect.origin = NSPoint(x: -1e7, y: -1e7)
        return clip.constrainBoundsRect(rect).origin
    }

    /// Scrolls to the top-left of the text (used when a tab is shown).
    func scrollToStart() {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        clip.scroll(to: startOrigin(of: clip))
        scrollView.reflectScrolledClipView(clip)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1, documentKind == .note else {
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

        if documentKind.isViewer {
            // Code is copied as exact plain text, line breaks and all — no colors or fonts.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString((string as NSString).substring(with: range), forType: .string)
            return
        }

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
