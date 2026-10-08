import AppKit

/// Colors and fonts for code and Markdown source. One palette (GitHub-style), with light
/// and dark variants that follow the app's appearance automatically.
enum CodeTheme {
    enum Role: Equatable {
        case keyword, string, comment, number, function, type, builtin, variable
        case attribute, tag, regexp, meta, `operator`, bracket
        case heading, emphasis, strong, link, addition, deletion
    }

    static let fontSize: CGFloat = 12

    static var font: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.15
        let tab = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            .advancement(forGlyph: NSGlyph(32)).width * 4
        ps.defaultTabInterval = tab > 0 ? tab : 28
        ps.tabStops = []
        return [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: ps
        ]
    }

    static func color(for role: Role) -> NSColor {
        switch role {
        case .keyword:   return dynamic(light: 0xCF222E, dark: 0xFF7B72)
        case .string:    return dynamic(light: 0x0A3069, dark: 0xA5D6FF)
        case .comment:   return dynamic(light: 0x6E7781, dark: 0x8B949E)
        case .number:    return dynamic(light: 0x0550AE, dark: 0x79C0FF)
        case .function:  return dynamic(light: 0x8250DF, dark: 0xD2A8FF)
        case .type:      return dynamic(light: 0x953800, dark: 0xFFA657)
        case .builtin:   return dynamic(light: 0x953800, dark: 0xFFA657)
        case .variable:  return dynamic(light: 0x953800, dark: 0xFFA657)
        case .attribute: return dynamic(light: 0x0550AE, dark: 0x79C0FF)
        case .tag:       return dynamic(light: 0x116329, dark: 0x7EE787)
        case .regexp:    return dynamic(light: 0x116329, dark: 0x7EE787)
        case .meta:      return dynamic(light: 0x8250DF, dark: 0xD2A8FF)
        case .operator:  return dynamic(light: 0xCF222E, dark: 0xFF7B72)
        case .bracket:   return dynamic(light: 0x57606A, dark: 0xA0A8B2)
        case .heading:   return dynamic(light: 0x0550AE, dark: 0x79C0FF)
        case .emphasis:  return NSColor.textColor
        case .strong:    return NSColor.textColor
        case .link:      return dynamic(light: 0x0A3069, dark: 0xA5D6FF)
        case .addition:  return dynamic(light: 0x116329, dark: 0x7EE787)
        case .deletion:  return dynamic(light: 0x82071E, dark: 0xFFA198)
        }
    }

    static func font(for role: Role) -> NSFont? {
        switch role {
        case .heading, .strong:
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        case .emphasis, .comment:
            return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        default:
            return nil
        }
    }

    /// Maps a highlight.js class attribute ("hljs-title function_") to a role.
    static func role(forClasses classes: String) -> Role? {
        let parts = classes.split(separator: " ")
        guard let first = parts.first, first.hasPrefix("hljs-") else { return nil }
        let scope = first.dropFirst(5)
        let modifiers = Set(parts.dropFirst())

        switch scope {
        case "keyword", "doctag", "selector-tag", "bullet": return .keyword
        case "string", "char", "template-tag", "code": return .string
        case "comment", "quote": return .comment
        case "number", "literal", "symbol": return .number
        case "title": return modifiers.contains("class_") ? .type : .function
        case "type", "class": return .type
        case "built_in", "builtin-name": return .builtin
        case "variable", "template-variable": return modifiers.contains("language_") ? .keyword : .variable
        case "property", "attr", "attribute", "selector-attr", "selector-pseudo": return .attribute
        case "name", "selector-id", "selector-class": return .tag
        case "tag", "punctuation": return .bracket
        case "regexp": return .regexp
        case "link": return .link
        case "meta": return .meta
        case "operator": return .operator
        case "section": return .heading
        case "emphasis": return .emphasis
        case "strong": return .strong
        case "addition": return .addition
        case "deletion": return .deletion
        default: return nil
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    // MARK: - Applying

    /// Restyles the whole storage as code and colors it. Only attributes change; the
    /// characters (indentation, line breaks, everything) are left exactly as they are.
    static func apply(_ tokens: [HighlightToken]?, to storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        for token in tokens ?? [] where NSMaxRange(token.range) <= storage.length {
            storage.addAttribute(.foregroundColor, value: color(for: token.role), range: token.range)
            if let font = font(for: token.role) {
                storage.addAttribute(.font, value: font, range: token.range)
            }
        }
        storage.endEditing()
    }
}
