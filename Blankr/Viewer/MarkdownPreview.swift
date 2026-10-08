import SwiftUI
import WebKit

/// Rendered Markdown. The HTML is produced ahead of time by `SyntaxEngine`, so the web view
/// runs with JavaScript off and a strict content policy: a document can show text, images
/// and styling, but nothing in it can execute.
struct MarkdownPreview: NSViewRepresentable {
    let html: String
    /// The Markdown file's folder, so relative images and links resolve.
    let baseURL: URL?
    let zoom: CGFloat
    let onOpenFile: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenFile: onOpenFile)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        load(webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenFile = onOpenFile
        if webView.pageZoom != zoom {
            webView.pageZoom = zoom
        }
        if context.coordinator.loadedHTML != html || context.coordinator.loadedBase != baseURL {
            load(webView, context: context)
        }
    }

    private func load(_ webView: WKWebView, context: Context) {
        context.coordinator.loadedHTML = html
        context.coordinator.loadedBase = baseURL
        webView.pageZoom = zoom
        let body = baseURL.map { Self.inliningLocalImages(in: html, relativeTo: $0) } ?? html
        webView.loadHTMLString(Self.page(body: body), baseURL: baseURL)
    }

    /// WebKit won't read local files for an HTML string, so images the document references
    /// next to itself (`![](shot.png)`) are embedded as data URLs. Only image files are read.
    static func inliningLocalImages(in html: String, relativeTo base: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(<img\b[^>]*?\bsrc=")([^"]+)(")"#, options: [.caseInsensitive]) else {
            return html
        }
        let types: [String: String] = [
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            "webp": "image/webp", "svg": "image/svg+xml", "heic": "image/heic", "bmp": "image/bmp",
            "ico": "image/x-icon", "tif": "image/tiff", "tiff": "image/tiff"
        ]
        let ns = html as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let srcRange = match.range(at: 2)
            let src = ns.substring(with: srcRange).replacingOccurrences(of: "&amp;", with: "&")
            result += ns.substring(with: NSRange(location: cursor, length: srcRange.location - cursor))
            cursor = NSMaxRange(srcRange)

            var replacement = ns.substring(with: srcRange)
            let isRemote = src.contains("://") && !src.hasPrefix("file://")
            if !isRemote, !src.hasPrefix("data:"),
               let url = src.hasPrefix("file://") ? URL(string: src) : URL(string: src, relativeTo: base)?.absoluteURL,
               let mime = types[url.pathExtension.lowercased()],
               let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 20_000_000,
               let data = try? Data(contentsOf: url) {
                replacement = "data:\(mime);base64,\(data.base64EncodedString())"
            }
            result += replacement
        }
        result += ns.substring(from: cursor)
        return result
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onOpenFile: (URL) -> Void
        var loadedHTML: String?
        var loadedBase: URL?

        init(onOpenFile: @escaping (URL) -> Void) {
            self.onOpenFile = onOpenFile
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                // The initial load, and in-page jumps to #anchors.
                decisionHandler(.allow)
                return
            }
            if url.fragment != nil, let current = webView.url,
               url.absoluteString.hasPrefix(current.absoluteString.components(separatedBy: "#")[0]) {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if url.isFileURL {
                // Another local document: open it in a tab; anything else goes to its own app.
                let kind = DocumentKind.detect(url: url, text: "")
                if FileManager.default.fileExists(atPath: url.path), kind != .note || url.pathExtension == "txt" {
                    onOpenFile(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Page

    static func page(body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data: file:; media-src * file:; style-src 'unsafe-inline'; font-src data:">
        <meta name="color-scheme" content="light dark">
        <style>\(css)</style>
        </head>
        <body><article>\(body)</article></body>
        </html>
        """
    }

    private static let css = """
    :root {
      --fg: #1f2328; --muted: #59636e; --bg: transparent; --border: #d1d9e0; --soft: #f6f8fa;
      --link: #0969da; --code-bg: #f6f8fa; --mark: #fff8c5;
      --k: #cf222e; --s: #0a3069; --c: #6e7781; --n: #0550ae; --f: #8250df; --t: #953800;
      --tag: #116329; --del: #82071e; --del-bg: #ffebe9; --add-bg: #dafbe1;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #e6edf3; --muted: #9198a1; --border: #3d444d; --soft: #151b23;
        --link: #4493f8; --code-bg: #151b23; --mark: #bb800926;
        --k: #ff7b72; --s: #a5d6ff; --c: #8b949e; --n: #79c0ff; --f: #d2a8ff; --t: #ffa657;
        --tag: #7ee787; --del: #ffa198; --del-bg: #490202; --add-bg: #04260f;
      }
    }
    html { background: var(--bg); }
    body {
      margin: 0; color: var(--fg); background: var(--bg);
      font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased; word-wrap: break-word;
    }
    article { max-width: 860px; margin: 0 auto; padding: 36px 44px 64px; }
    article > :first-child { margin-top: 0 !important; }
    h1, h2, h3, h4, h5, h6 { margin: 1.5em 0 0.6em; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    p, ul, ol, blockquote, table, pre, dl { margin: 0 0 1em; }
    a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
    ul, ol { padding-left: 2em; } li + li { margin-top: .25em; }
    li > input[type=checkbox] { margin: 0 .4em .2em -1.4em; vertical-align: middle; }
    li:has(> input[type=checkbox]) { list-style: none; }
    blockquote { padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); }
    hr { height: .25em; margin: 1.5em 0; background: var(--border); border: 0; }
    img { max-width: 100%; }
    table { border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; } tr:nth-child(2n) { background: var(--soft); }
    code, pre { font: 12.5px/1.5 ui-monospace, "SF Mono", Menlo, monospace; }
    :not(pre) > code { padding: .2em .4em; background: var(--code-bg); border-radius: 6px; font-size: 85%; }
    pre { position: relative; padding: 16px; overflow: auto; background: var(--code-bg); border-radius: 8px; }
    pre > code { white-space: pre; tab-size: 4; }
    pre > .lang {
      position: absolute; top: 6px; right: 10px; font: 11px -apple-system, sans-serif;
      color: var(--muted); text-transform: lowercase; user-select: none;
    }
    pre.front-matter { border-left: 3px solid var(--border); }
    mark { background: var(--mark); color: inherit; }
    del { color: var(--muted); }
    kbd {
      padding: 2px 5px; font: 11px ui-monospace, monospace; border: 1px solid var(--border);
      border-bottom-width: 2px; border-radius: 4px; background: var(--soft);
    }
    details { margin-bottom: 1em; } summary { cursor: pointer; }
    .hljs-keyword, .hljs-doctag, .hljs-selector-tag, .hljs-bullet, .hljs-operator,
    .hljs-variable.language_ { color: var(--k); }
    .hljs-string, .hljs-char, .hljs-template-tag, .hljs-link, .hljs-code { color: var(--s); }
    .hljs-comment, .hljs-quote { color: var(--c); font-style: italic; }
    .hljs-number, .hljs-literal, .hljs-symbol, .hljs-attr, .hljs-attribute, .hljs-property,
    .hljs-selector-attr, .hljs-selector-pseudo { color: var(--n); }
    .hljs-title, .hljs-title.function_, .hljs-meta { color: var(--f); }
    .hljs-title.class_, .hljs-type, .hljs-built_in, .hljs-variable, .hljs-template-variable { color: var(--t); }
    .hljs-name, .hljs-selector-id, .hljs-selector-class, .hljs-regexp { color: var(--tag); }
    .hljs-section { color: var(--n); font-weight: 600; }
    .hljs-emphasis { font-style: italic; } .hljs-strong { font-weight: 600; }
    .hljs-addition { color: var(--tag); background: var(--add-bg); }
    .hljs-deletion { color: var(--del); background: var(--del-bg); }
    """
}
