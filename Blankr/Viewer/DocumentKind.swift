import Foundation

/// How a tab presents its file. Notes are the rich-text editor; Markdown and code are
/// viewer-first (rendered or syntax-highlighted), with editing opt-in.
enum DocumentKind: Equatable {
    case note
    case markdown
    /// A highlight.js language id ("python", "typescript"…); "plaintext" means monospaced, uncolored.
    case code(String)

    var isViewer: Bool { self != .note }

    /// The language used to color the editable source, if any.
    var sourceLanguage: String? {
        switch self {
        case .note: return nil
        case .markdown: return "markdown"
        case .code(let language): return language
        }
    }

    var displayName: String {
        switch self {
        case .note: return "Note"
        case .markdown: return "Markdown"
        case .code(let language): return SyntaxEngine.shared.displayName(for: language)
        }
    }

    // MARK: - Detection

    static func detect(url: URL?, text: String) -> DocumentKind {
        guard let url else { return .note }
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if ["txt", "text", "rtf"].contains(ext) { return .note }
        if markdownExtensions.contains(ext) { return .markdown }
        if let language = fileNames[name] ?? fileNames[name.lowercased()] { return .code(language) }
        if name.hasPrefix("Dockerfile") || name.hasSuffix(".dockerfile") { return .code("dockerfile") }
        if let language = extensions[ext] { return .code(language) }
        if let language = shebangLanguage(text) { return .code(language) }

        // Unknown type: let highlight.js guess, and only trust a confident answer.
        if let guess = SyntaxEngine.shared.detectLanguage(text) { return .code(guess) }
        return .note
    }

    private static func shebangLanguage(_ text: String) -> String? {
        guard text.hasPrefix("#!") else { return nil }
        let firstLine = text.prefix { $0 != "\n" }.lowercased()
        let table: [(String, String)] = [
            ("python", "python"), ("node", "javascript"), ("deno", "typescript"), ("ts-node", "typescript"),
            ("bash", "bash"), ("zsh", "bash"), ("/sh", "bash"), (" sh", "bash"), ("fish", "bash"),
            ("ruby", "ruby"), ("perl", "perl"), ("php", "php"), ("osascript", "applescript"),
            ("swift", "swift"), ("lua", "lua"), ("rscript", "r"), ("julia", "julia"), ("pwsh", "powershell")
        ]
        return table.first { firstLine.contains($0.0) }?.1
    }

    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx"
    ]

    private static let fileNames: [String: String] = [
        "Makefile": "makefile", "makefile": "makefile", "GNUmakefile": "makefile",
        "CMakeLists.txt": "cmake",
        "Gemfile": "ruby", "Rakefile": "ruby", "Podfile": "ruby", "Fastfile": "ruby",
        "Brewfile": "ruby", "Vagrantfile": "ruby", "Appfile": "ruby", "Dangerfile": "ruby",
        "Jenkinsfile": "groovy",
        ".bashrc": "bash", ".bash_profile": "bash", ".zshrc": "bash", ".zprofile": "bash",
        ".profile": "bash", ".zshenv": "bash", ".env": "bash",
        ".gitignore": "bash", ".dockerignore": "bash", ".gitattributes": "plaintext",
        ".editorconfig": "ini", ".npmrc": "ini", ".gitconfig": "ini",
        ".htaccess": "apache", "httpd.conf": "apache", "nginx.conf": "nginx",
        "Procfile": "plaintext", "LICENSE": "plaintext", "Pipfile": "ini"
    ]

    private static let extensions: [String: String] = {
        var map: [String: String] = [:]
        func add(_ language: String, _ exts: String) {
            for ext in exts.split(separator: " ") { map[String(ext)] = language }
        }
        add("javascript", "js mjs cjs jsx")
        add("typescript", "ts mts cts tsx")
        add("python", "py pyw pyi pyx")
        add("ruby", "rb rake gemspec ru podspec")
        add("java", "java")
        add("kotlin", "kt kts")
        add("swift", "swift")
        add("objectivec", "m mm")
        add("c", "c")
        add("cpp", "h hh hpp hxx h++ cc cpp cxx c++ ino ipp tpp")
        add("csharp", "cs csx")
        add("go", "go")
        add("rust", "rs")
        add("php", "php phtml php3 php4 php5 phps")
        add("xml", "html htm xhtml xml plist svg xsd xsl xslt rss atom csproj vbproj fsproj storyboard xib vue svelte astro erb ejs jsp aspx cshtml razor wsdl")
        add("css", "css")
        add("scss", "scss sass")
        add("less", "less")
        add("json", "json jsonc json5 geojson webmanifest har ipynb babelrc eslintrc prettierrc jsonl")
        add("yaml", "yaml yml")
        add("ini", "toml ini cfg conf cnf inf")
        add("properties", "properties")
        add("bash", "sh bash zsh fish ksh command")
        add("powershell", "ps1 psm1 psd1")
        add("dos", "bat cmd")
        add("sql", "sql psql mysql pgsql")
        add("graphql", "graphql gql")
        add("r", "r rmd")
        add("lua", "lua")
        add("perl", "pl pm t pod")
        add("dart", "dart")
        add("scala", "scala sc sbt")
        add("haskell", "hs lhs")
        add("elixir", "ex exs")
        add("erlang", "erl hrl")
        add("clojure", "clj cljs cljc edn")
        add("groovy", "groovy gvy")
        add("gradle", "gradle")
        add("julia", "jl")
        add("ocaml", "ml mli")
        add("fsharp", "fs fsi fsx")
        add("latex", "tex sty cls bib")
        add("protobuf", "proto")
        add("cmake", "cmake")
        add("vim", "vim vimrc")
        add("x86asm", "asm nasm")
        add("armasm", "s")
        add("fortran", "f f90 f95 f03 for")
        add("delphi", "pas dpr lpr")
        add("lisp", "lisp lsp el cl")
        add("scheme", "scm ss rkt")
        add("tcl", "tcl")
        add("verilog", "v sv svh vh")
        add("vhdl", "vhd vhdl")
        add("nim", "nim nims")
        add("crystal", "cr")
        add("d", "d")
        add("coffeescript", "coffee")
        add("handlebars", "hbs handlebars mustache")
        add("twig", "twig")
        add("django", "jinja jinja2 j2 djhtml")
        add("http", "http")
        add("diff", "diff patch")
        add("makefile", "mk mak")
        add("vbnet", "vb")
        add("wasm", "wat wast")
        add("elm", "elm")
        add("reasonml", "re rei")
        add("llvm", "ll")
        add("glsl", "glsl vert frag geom comp")
        add("haxe", "hx")
        add("applescript", "applescript")
        add("actionscript", "as")
        add("ada", "adb ads")
        add("smalltalk", "st")
        add("awk", "awk")
        add("prolog", "pro")
        add("plaintext", "log csv tsv lock")
        return map
    }()
}
