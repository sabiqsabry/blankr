import SwiftUI

struct ContentView: View {
    @ObservedObject private var session = NoteSession.shared
    @State private var renamingTabId: UUID?
    @State private var renameDraft = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            HStack(spacing: 0) {
                RichTextEditor(session: session)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                FormattingPanel(session: session)
            }
        }
        .onChange(of: renamingTabId) { newId in
            if newId != nil {
                DispatchQueue.main.async {
                    renameFieldFocused = true
                }
            }
        }
    }

    private func finalizeRenameIfNeeded() {
        if let id = renamingTabId {
            session.commitTabTitle(id: id)
            renamingTabId = nil
            renameFieldFocused = false
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(session.tabs) { tab in
                        tabCell(tab)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)

            Button(action: {
                finalizeRenameIfNeeded()
                session.addTab()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .help("New tab")
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func tabCell(_ tab: EditorTab) -> some View {
        let selected = tab.id == session.selectedTabId
        return HStack(spacing: 2) {
            Group {
                if renamingTabId == tab.id {
                    TextField("Untitled", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($renameFieldFocused)
                        .frame(minWidth: 64, maxWidth: 160)
                        .onChange(of: renameDraft) { newValue in
                            session.updateTabTitleDraft(id: tab.id, draft: newValue)
                        }
                        .onSubmit {
                            finalizeRenameIfNeeded()
                        }
                } else {
                    TabTitleLabel(
                        title: session.title(for: tab),
                        isSelected: selected,
                        onSelect: {
                            finalizeRenameIfNeeded()
                            session.selectTab(id: tab.id)
                        },
                        onRename: {
                            renameDraft = tab.customTitle ?? ""
                            renamingTabId = tab.id
                        }
                    )
                    .frame(minWidth: 48, maxWidth: 160, maxHeight: 22)
                }
            }

            Button(action: {
                if renamingTabId == tab.id {
                    session.commitTabTitle(id: tab.id)
                    renamingTabId = nil
                    renameFieldFocused = false
                }
                session.closeTab(id: tab.id)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}
