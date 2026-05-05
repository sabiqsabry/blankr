import SwiftUI

struct FormattingPanel: View {
    @ObservedObject var session: NoteSession
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var showingInfo = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 12)

            toolButton(icon: "bold", active: session.isBold) {
                guard let tv = session.textView else { return }
                FormattingActions.toggleBold(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "italic", active: session.isItalic) {
                guard let tv = session.textView else { return }
                FormattingActions.toggleItalic(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "underline", active: session.isUnderline) {
                guard let tv = session.textView else { return }
                FormattingActions.toggleUnderline(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Divider()
                .frame(width: 24)
                .padding(.vertical, 2)

            toolButton(icon: "plus", active: false) {
                guard let tv = session.textView else { return }
                FormattingActions.adjustFontSize(by: 1, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Text("\(Int(session.fontSize))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            toolButton(icon: "minus", active: false) {
                guard let tv = session.textView else { return }
                FormattingActions.adjustFontSize(by: -1, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Divider()
                .frame(width: 24)
                .padding(.vertical, 2)

            toolButton(icon: "text.alignleft", active: session.alignment == .left) {
                guard let tv = session.textView else { return }
                FormattingActions.setAlignment(.left, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "text.aligncenter", active: session.alignment == .center) {
                guard let tv = session.textView else { return }
                FormattingActions.setAlignment(.center, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            toolButton(icon: "text.alignright", active: session.alignment == .right) {
                guard let tv = session.textView else { return }
                FormattingActions.setAlignment(.right, textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Divider()
                .frame(width: 24)
                .padding(.vertical, 2)

            toolButton(icon: "checklist", active: session.isOnChecklistLine) {
                guard let tv = session.textView else { return }
                FormattingActions.insertChecklistItem(textView: tv)
                session.updateFormattingState()
                session.refocus()
            }

            Toggle(isOn: $session.copyPreservesLineBreaks) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Include line breaks when copying")
            .help("Include line breaks when copying")
            .padding(.vertical, 2)

            Spacer()

            toolButton(icon: isDarkMode ? "sun.max.fill" : "moon.fill", active: false) {
                isDarkMode.toggle()
            }
            .padding(.bottom, 4)

            Button(action: { showingInfo.toggle() }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.quaternary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
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
            .padding(.bottom, 12)
        }
        .frame(width: 44)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func toolButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
