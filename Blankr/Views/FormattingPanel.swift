import SwiftUI

struct FormattingPanel: View {
    @ObservedObject var session: NoteSession
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var showingInfo = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        // At high zoom the tools can be taller than the window; scroll then, but otherwise
        // fill the height so the theme and info buttons stay pinned to the bottom.
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                tools
                    .frame(minHeight: geometry.size.height)
            }
        }
        .frame(width: 44 * scale)
        .background(Chrome.background)
        .chromeEdge(.leading)
    }

    private var tools: some View {
        VStack(spacing: 10 * scale) {
            Spacer().frame(height: 12 * scale)

            if session.activeKind.isViewer {
                viewerTools
            } else {
                noteTools
            }

            Spacer()

            footer
        }
        .frame(width: 44 * scale)
    }

    /// Markdown: preview / edit source. Code: read-only / editable, plus line wrapping.
    @ViewBuilder
    private var viewerTools: some View {
        let tab = session.activeTab
        let editing = tab?.isEditing ?? false

        if session.activeKind == .markdown {
            toolButton(icon: "eye", active: !editing, help: "Preview") {
                session.setEditing(false)
            }
            toolButton(icon: "pencil", active: editing, help: "Edit Markdown source") {
                session.setEditing(true)
            }
        } else {
            toolButton(icon: editing ? "pencil" : "lock", active: editing,
                       help: editing ? "Editing — click to make read-only" : "Read-only — click to edit") {
                session.setEditing(!editing)
            }
        }

        if session.activeKind != .markdown || editing {
            divider
            lineNumbersButton
            toolButton(icon: "arrow.turn.down.left", active: tab?.wrapsLines ?? false, help: "Wrap long lines") {
                session.setWrapsLines(!(tab?.wrapsLines ?? false))
            }
        }
    }

    private var lineNumbersButton: some View {
        // "#" rather than a list icon, so it isn't mistaken for the numbered-list button.
        toolButton(icon: "number", active: session.showLineNumbers,
                   help: session.showLineNumbers ? "Hide line numbers (⌥⌘L)" : "Show line numbers (⌥⌘L)") {
            session.showLineNumbers.toggle()
        }
    }

    private var divider: some View {
        Divider()
            .frame(width: 24 * scale)
            .padding(.vertical, 2 * scale)
    }

    @ViewBuilder
    private var noteTools: some View {
            toolButton(icon: "bold", active: session.isBold, help: "Bold") {
                guard let tv = session.textView else { return }
                FormattingActions.toggleBold(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "italic", active: session.isItalic, help: "Italic") {
                guard let tv = session.textView else { return }
                FormattingActions.toggleItalic(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "underline", active: session.isUnderline, help: "Underline") {
                guard let tv = session.textView else { return }
                FormattingActions.toggleUnderline(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Divider()
                .frame(width: 24 * scale)
                .padding(.vertical, 2 * scale)

            toolButton(icon: "plus", active: false, help: "Larger text") {
                guard let tv = session.textView else { return }
                FormattingActions.adjustFontSize(by: 1, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Text("\(Int(session.fontSize))")
                .font(.system(size: 10 * scale, design: .monospaced))
                .foregroundStyle(.tertiary)

            toolButton(icon: "minus", active: false, help: "Smaller text") {
                guard let tv = session.textView else { return }
                FormattingActions.adjustFontSize(by: -1, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Divider()
                .frame(width: 24 * scale)
                .padding(.vertical, 2 * scale)

            toolButton(icon: "text.alignleft", active: session.alignment == .left, help: "Align left") {
                guard let tv = session.textView else { return }
                FormattingActions.setAlignment(.left, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "text.aligncenter", active: session.alignment == .center, help: "Center") {
                guard let tv = session.textView else { return }
                FormattingActions.setAlignment(.center, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "text.alignright", active: session.alignment == .right, help: "Align right") {
                guard let tv = session.textView else { return }
                FormattingActions.setAlignment(.right, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Divider()
                .frame(width: 24 * scale)
                .padding(.vertical, 2 * scale)

            toolButton(icon: "checklist", active: session.isOnChecklistLine, help: "Checklist") {
                guard let tv = session.textView else { return }
                FormattingActions.insertChecklistItem(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "list.number", active: session.isOnNumberedLine, help: "Numbered list") {
                guard let tv = session.textView else { return }
                FormattingActions.toggleNumberedItem(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            divider

            lineNumbersButton

            Toggle(isOn: $session.copyPreservesLineBreaks) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12 * scale))
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Include line breaks when copying")
            .help("Include line breaks when copying")
            .padding(.vertical, 2 * scale)
    }

    @ViewBuilder
    private var footer: some View {
            toolButton(icon: isDarkMode ? "sun.max.fill" : "moon.fill", active: false, help: isDarkMode ? "Light mode" : "Dark mode") {
                isDarkMode.toggle()
            }
            .padding(.bottom, 4 * scale)

            Button(action: { showingInfo.toggle() }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.quaternary)
                    .frame(width: 28 * scale, height: 28 * scale)
            }
            .buttonStyle(.pressable)
            .popover(isPresented: $showingInfo, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blankr.")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Sabiq Sabry")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("novusian")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\u{00A9} 2026 novusian. All rights reserved.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .padding(14)
            }
            .padding(.bottom, 12 * scale)
    }

    private func toolButton(icon: String, active: Bool, help: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13 * scale, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 28 * scale, height: 28 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 5 * scale)
                        .fill(active ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                // Turning a style on or off fades rather than snapping.
                .animation(.easeOut(duration: 0.18), value: active)
        }
        .buttonStyle(.pressable)
        .help(help)
    }
}
