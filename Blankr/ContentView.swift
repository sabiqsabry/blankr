import SwiftUI

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// App-wide zoom. Chrome multiplies its sizes by this so it stays crisp at any zoom.
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

/// Colors for the UI around the writing area. Dark mode keeps the system look (which already
/// separates chrome from the editor); light mode gets a soft grey and hairlines, since the
/// system window background there is as white as the editor itself.
enum Chrome {
    static let background = dynamic(
        light: NSColor(srgbRed: 0.957, green: 0.957, blue: 0.949, alpha: 1),
        dark: NSColor.windowBackgroundColor.withAlphaComponent(0.5)
    )
    static let separator = dynamic(
        light: NSColor(srgbRed: 0.878, green: 0.878, blue: 0.867, alpha: 1),
        dark: .clear
    )
    /// Selected tab: a white chip in light mode (with the accent tint on top).
    static let selectedTabBase = dynamic(light: .white, dark: .clear)
    static let idleTab = dynamic(light: NSColor.black.withAlphaComponent(0.035), dark: .clear)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    /// A 1pt hairline on one edge (light mode only; clear in dark mode).
    func chromeEdge(_ edge: Alignment) -> some View {
        overlay(alignment: edge) {
            if edge == .leading || edge == .trailing {
                Rectangle().fill(Chrome.separator).frame(width: 1)
            } else {
                Rectangle().fill(Chrome.separator).frame(height: 1)
            }
        }
    }
}

struct ContentView: View {
    /// The user's zoom (⌘= / ⌘-), relative to the display's comfortable default.
    let uiScale: Double

    @ObservedObject private var session = NoteSession.shared
    @ObservedObject private var display = DisplayScale.shared
    @State private var renamingTabId: UUID?
    @State private var renameDraft = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var zoomBadgeVisible = false
    @State private var zoomBadgeHide: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        RichTextEditor(session: session, zoom: scale)
                        if let preview = session.preview {
                            markdownPreview(preview)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                    if let tab = session.activeTab, tab.kind.isViewer {
                        statusBar(tab)
                    }
                }

                FormattingPanel(session: session)
            }
        }
        .environment(\.uiScale, scale)
        .overlay(alignment: .top) { zoomBadge }
        .onChange(of: renamingTabId) { newId in
            if newId != nil {
                DispatchQueue.main.async {
                    renameFieldFocused = true
                }
            }
        }
        .onChange(of: uiScale) { _ in
            showZoomBadge()
        }
    }

    /// Display default × user zoom, kept within readable bounds.
    private var scale: CGFloat {
        min(3, max(0.5, display.factor * CGFloat(uiScale)))
    }

    @ViewBuilder
    private func markdownPreview(_ preview: NoteSession.Preview) -> some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            if let html = preview.html {
                MarkdownPreview(html: html, baseURL: preview.baseURL, zoom: scale) { url in
                    session.openFiles(urls: [url])
                }
            }
        }
    }

    private func statusBar(_ tab: EditorTab) -> some View {
        let mode: String
        switch tab.kind {
        case .markdown: mode = tab.isEditing ? "Editing source" : "Preview"
        default: mode = tab.isEditing ? "Editing" : "Read-only"
        }
        let lines = session.activeLineCount
        return HStack(spacing: 6 * scale) {
            Text(tab.kind.displayName)
            Text("·")
            Text("\(lines) line\(lines == 1 ? "" : "s")")
            Spacer()
            Text(mode)
        }
        .font(.system(size: 10.5 * scale))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12 * scale)
        .frame(height: 22 * scale)
        .background(Chrome.background)
        .chromeEdge(.top)
        .help(tab.fileURL?.path ?? "")
    }

    private var zoomBadge: some View {
        Text("\(Int((uiScale * 100).rounded()))%")
            .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 6 * scale)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 48 * scale)
            .opacity(zoomBadgeVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: zoomBadgeVisible)
            .allowsHitTesting(false)
    }

    private func showZoomBadge() {
        zoomBadgeVisible = true
        zoomBadgeHide?.cancel()
        let hide = DispatchWorkItem { zoomBadgeVisible = false }
        zoomBadgeHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: hide)
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
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4 * scale) {
                        ForEach(session.tabs) { tab in
                            tabCell(tab)
                                .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 6 * scale)
                }
                // Keep the selected tab in view when there are more tabs than fit.
                .onChange(of: session.selectedTabId) { id in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: {
                finalizeRenameIfNeeded()
                session.addTab()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28 * scale, height: 28 * scale)
            }
            .buttonStyle(.pressable)
            .padding(.trailing, 10 * scale)
            .help("New tab")
        }
        .background(Chrome.background)
        .chromeEdge(.bottom)
    }

    private func tabCell(_ tab: EditorTab) -> some View {
        let selected = tab.id == session.selectedTabId
        return HStack(spacing: 2 * scale) {
            Group {
                if renamingTabId == tab.id {
                    TextField("Untitled", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12 * scale))
                        .focused($renameFieldFocused)
                        .frame(minWidth: 64 * scale, maxWidth: 160 * scale)
                        .onChange(of: renameDraft) { newValue in
                            session.updateTabTitleDraft(id: tab.id, draft: newValue)
                        }
                        .onSubmit {
                            finalizeRenameIfNeeded()
                        }
                } else {
                    TabTitleLabel(
                        title: session.title(for: tab),
                        toolTip: tab.fileURL?.path,
                        isSelected: selected,
                        fontSize: 12 * scale,
                        onSelect: {
                            finalizeRenameIfNeeded()
                            session.selectTab(id: tab.id)
                        },
                        onRename: {
                            renameDraft = tab.customTitle ?? ""
                            renamingTabId = tab.id
                        }
                    )
                    .frame(minWidth: 48 * scale, maxWidth: 160 * scale, maxHeight: 22 * scale)
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
                    .font(.system(size: 9 * scale, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16 * scale, height: 16 * scale)
            }
            .buttonStyle(.pressable)
            .help("Close tab")
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 4 * scale)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 5 * scale)
                    .fill(selected ? Chrome.selectedTabBase : Chrome.idleTab)
                RoundedRectangle(cornerRadius: 5 * scale)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                RoundedRectangle(cornerRadius: 5 * scale)
                    .strokeBorder(selected ? Chrome.separator : Color.clear, lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.18), value: selected)
        )
    }
}
