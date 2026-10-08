import AppKit
import JavaScriptCore

/// A colored span of source text. Ranges are UTF-16, ready for NSTextStorage.
struct HighlightToken {
    let range: NSRange
    let role: CodeTheme.Role
}

/// Runs the bundled highlight.js and marked in a private JavaScriptCore context.
/// Everything happens on one serial queue; results come back on the main queue.
/// No web page and no network are involved.
final class SyntaxEngine {
    static let shared = SyntaxEngine()

    /// Past this size, files are shown monospaced but uncolored so they open instantly.
    static let maxHighlightLength = 1_000_000

    private let queue = DispatchQueue(label: "app.blankr.syntax", qos: .userInitiated)
    private var context: JSContext?
    private var displayNames: [String: String] = [:]

    private init() {}

    // MARK: - Public API

    /// Colors `text` as `language`. The completion gets nil if highlighting was not possible;
    /// the text itself is never changed, only described.
    func highlight(_ text: String, language: String, completion: @escaping ([HighlightToken]?) -> Void) {
        guard language != "plaintext", (text as NSString).length <= Self.maxHighlightLength else {
            completion(nil)
            return
        }
        queue.async {
            let tokens = self.highlightSync(text, language: language)
            DispatchQueue.main.async { completion(tokens) }
        }
    }

    func renderMarkdown(_ source: String, completion: @escaping (String) -> Void) {
        queue.async {
            let html = self.call("blankrMarkdown", [source])?.toString()
                ?? "<pre>" + Self.escapeHTML(source) + "</pre>"
            DispatchQueue.main.async { completion(html) }
        }
    }

    /// A confident guess at the language of unlabeled text, or nil.
    func detectLanguage(_ text: String) -> String? {
        let sample = String(text.prefix(8_000))
        guard !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return queue.sync {
            guard let value = call("blankrDetect", [sample]), value.isString else { return nil }
            return value.toString()
        }
    }

    func displayName(for language: String) -> String {
        if language == "plaintext" { return "Plain Text" }
        if language == "xml" { return "HTML / XML" }
        if let cached = displayNames[language] { return cached }
        let name = queue.sync { call("blankrLanguageName", [language])?.toString() }
        let resolved = (name?.isEmpty == false && name != "undefined") ? name! : language.capitalized
        displayNames[language] = resolved
        return resolved
    }

    // MARK: - JavaScript

    private func call(_ function: String, _ args: [Any]) -> JSValue? {
        guard let ctx = loadedContext(), let fn = ctx.objectForKeyedSubscript(function),
              !fn.isUndefined else { return nil }
        let result = fn.call(withArguments: args)
        if ctx.exception != nil {
            ctx.exception = nil
            return nil
        }
        guard let result, !result.isNull, !result.isUndefined else { return nil }
        return result
    }

    private func loadedContext() -> JSContext? {
        if let context { return context }
        guard let ctx = JSContext() else { return nil }
        ctx.evaluateScript("var console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };")
        for name in ["highlight.bundle", "marked.min"] {
            guard let url = Self.resourceURL(name, "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            ctx.evaluateScript(source, withSourceURL: url)
        }
        ctx.evaluateScript(Self.bridgeScript)
        guard ctx.exception == nil else { return nil }
        context = ctx
        return ctx
    }

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ThirdParty")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    private static let bridgeScript = #"""
    function blankrEscape(s) {
      return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    function blankrHighlight(code, lang) {
      if (!hljs.getLanguage(lang)) return null;
      return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
    }
    // Languages whose grammars also match ordinary prose; never auto-pick them.
    var blankrNoisy = ['vim', 'apache', 'nginx', 'markdown', 'plaintext', 'dos', 'awk', 'http', 'prolog', 'smalltalk', 'delphi'];
    function blankrDetect(code) {
      var subset = hljs.listLanguages().filter(function (l) { return blankrNoisy.indexOf(l) < 0; });
      var r = hljs.highlightAuto(code, subset);
      return (r.language && r.relevance >= 7) ? r.language : null;
    }
    function blankrLanguageName(lang) {
      var l = hljs.getLanguage(lang);
      return l ? l.name : null;
    }
    function blankrSlug(raw) {
      return raw.toLowerCase().trim().replace(/[^\w\- ]+/g, '').replace(/\s+/g, '-');
    }
    function blankrCode(code, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try { return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value; } catch (e) {}
      }
      return blankrEscape(code);
    }
    marked.use({
      gfm: true,
      renderer: {
        code: function (code, info) {
          var lang = (info || '').trim().split(/\s+/)[0].toLowerCase();
          var label = lang ? '<span class="lang">' + blankrEscape(lang) + '</span>' : '';
          return '<pre>' + label + '<code class="hljs">' + blankrCode(code, lang) + '</code></pre>\n';
        },
        heading: function (text, level, raw) {
          return '<h' + level + ' id="' + blankrSlug(raw) + '">' + text + '</h' + level + '>\n';
        }
      }
    });
    function blankrMarkdown(src) {
      var front = '';
      var m = /^---\r?\n([\s\S]*?)\r?\n---[ \t]*(\r?\n|$)/.exec(src);
      if (m) {
        front = '<pre class="front-matter"><code class="hljs">' + blankrCode(m[1], 'yaml') + '</code></pre>\n';
        src = src.slice(m[0].length);
      }
      return front + marked.parse(src);
    }
    """#

    // MARK: - Turning highlight.js HTML into ranges

    private func highlightSync(_ text: String, language: String) -> [HighlightToken]? {
        guard let html = call("blankrHighlight", [text, language])?.toString() else { return nil }
        let source = text as NSString
        guard var tokens = Self.tokens(fromHTML: html, expectedLength: source.length) else { return nil }
        if !Self.languagesWithoutOperatorPass.contains(language) {
            tokens = Self.addingOperatorsAndBrackets(to: tokens, source: source)
        }
        return tokens
    }

    /// Markup-like languages where coloring `*`, `#`, `<` etc. would be noise.
    private static let languagesWithoutOperatorPass: Set<String> = [
        "markdown", "plaintext", "latex", "xml", "diff", "http", "properties", "ini",
        "css", "scss", "less", "yaml"
    ]

    /// Walks highlight.js output (`<span class="hljs-…">` + escaped text) and returns the
    /// colored ranges. Returns nil unless the decoded text length matches the source exactly,
    /// so a parse mismatch can never shift colors onto the wrong characters.
    static func tokens(fromHTML html: String, expectedLength: Int) -> [HighlightToken]? {
        let s = html as NSString
        let n = s.length
        var i = 0
        var position = 0
        var stack: [CodeTheme.Role?] = []
        var tokens: [HighlightToken] = []

        func emit(_ length: Int) {
            guard length > 0 else { return }
            if let role = stack.last(where: { $0 != nil }) ?? nil {
                if let last = tokens.last, last.role == role, NSMaxRange(last.range) == position {
                    tokens[tokens.count - 1] = HighlightToken(
                        range: NSRange(location: last.range.location, length: last.range.length + length),
                        role: role
                    )
                } else {
                    tokens.append(HighlightToken(range: NSRange(location: position, length: length), role: role))
                }
            }
            position += length
        }

        let lt = UInt16(UInt8(ascii: "<")), amp = UInt16(UInt8(ascii: "&"))
        while i < n {
            let c = s.character(at: i)
            if c == lt {
                if s.length - i >= 7, s.substring(with: NSRange(location: i, length: 7)) == "</span>" {
                    guard !stack.isEmpty else { return nil }
                    stack.removeLast()
                    i += 7
                } else if s.length - i >= 13, s.substring(with: NSRange(location: i, length: 13)) == "<span class=\"" {
                    let close = s.range(of: "\">", range: NSRange(location: i + 13, length: n - i - 13))
                    guard close.location != NSNotFound else { return nil }
                    let classes = s.substring(with: NSRange(location: i + 13, length: close.location - i - 13))
                    stack.append(CodeTheme.role(forClasses: classes))
                    i = NSMaxRange(close)
                } else {
                    return nil
                }
            } else if c == amp {
                let semi = s.range(of: ";", range: NSRange(location: i, length: min(10, n - i)))
                guard semi.location != NSNotFound else { return nil }
                emit(1)
                i = NSMaxRange(semi)
            } else {
                var j = i
                while j < n {
                    let d = s.character(at: j)
                    if d == lt || d == amp { break }
                    j += 1
                }
                emit(j - i)
                i = j
            }
        }
        guard stack.isEmpty, position == expectedLength else { return nil }
        return tokens
    }

    /// highlight.js leaves most operators and brackets unmarked; color them in the gaps
    /// between its tokens (never inside strings or comments, which are already tokens).
    private static func addingOperatorsAndBrackets(to tokens: [HighlightToken], source: NSString) -> [HighlightToken] {
        let brackets = Set("()[]{}".utf16)
        let operators = Set("+-*/%=<>!&|^~?:".utf16)
        var result: [HighlightToken] = []
        result.reserveCapacity(tokens.count * 2)

        func isWordCharacter(_ index: Int) -> Bool {
            guard index >= 0, index < source.length, let scalar = Unicode.Scalar(source.character(at: index)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        let hyphen = UInt16(UInt8(ascii: "-"))

        func scanGap(_ start: Int, _ end: Int) {
            var k = start
            while k < end {
                let c = source.character(at: k)
                // A hyphen inside a word ("ubuntu-latest", "build-dmg") is part of the name.
                if c == hyphen, isWordCharacter(k - 1), isWordCharacter(k + 1) {
                    k += 1
                    continue
                }
                let role: CodeTheme.Role? = brackets.contains(c) ? .bracket : (operators.contains(c) ? .operator : nil)
                guard let role else { k += 1; continue }
                var m = k + 1
                while m < end, role == .operator, operators.contains(source.character(at: m)) { m += 1 }
                result.append(HighlightToken(range: NSRange(location: k, length: m - k), role: role))
                k = m
            }
        }

        var cursor = 0
        for token in tokens {
            scanGap(cursor, token.range.location)
            result.append(token)
            cursor = NSMaxRange(token.range)
        }
        scanGap(cursor, source.length)
        return result
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
