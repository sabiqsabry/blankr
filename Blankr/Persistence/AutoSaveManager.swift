import AppKit

/// Reading and writing note files. Plain-text files stay plain text; notes that carry
/// formatting are written as RTF so bold, size, underline and alignment survive.
enum DocumentIO {
    enum ReadError: Error {
        case undecodable
    }

    static func isRichText(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "rtf"
    }

    static func read(url: URL) throws -> NSAttributedString {
        if isRichText(url) {
            let raw = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return normalizedAfterRTFRead(raw)
        }

        let data = try Data(contentsOf: url)
        let text: String
        let bom = [UInt8](data.prefix(2))
        if bom == [0xFF, 0xFE] || bom == [0xFE, 0xFF], let utf16 = String(data: data, encoding: .utf16) {
            text = utf16
        } else if data.prefix(8_192).contains(0) {
            // NUL bytes outside UTF-16 mean a binary file (image, archive, executable).
            throw ReadError.undecodable
        } else if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            var encoding = String.Encoding.utf8
            guard let detected = try? String(contentsOf: url, usedEncoding: &encoding) else {
                throw ReadError.undecodable
            }
            text = detected
        }
        return NSAttributedString(string: text, attributes: NoteSession.defaultAttributes)
    }

    static func write(_ content: NSAttributedString, to url: URL) throws {
        if isRichText(url) {
            let data = try rtfData(content)
            try data.write(to: url, options: .atomic)
        } else {
            try content.string.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// True when the note uses anything a .txt file can't hold.
    static func hasFormatting(_ content: NSAttributedString) -> Bool {
        var found = false
        let full = NSRange(location: 0, length: content.length)
        content.enumerateAttributes(in: full) { attrs, _, stop in
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) || traits.contains(.italic)
                    || font.pointSize != NoteSession.defaultFontSize {
                    found = true
                }
            }
            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                found = true
            }
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle,
               ps.alignment != .left, ps.alignment != .natural {
                found = true
            }
            if found { stop.pointee = true }
        }
        return found
    }

    // MARK: - RTF

    private static func rtfData(_ content: NSAttributedString) throws -> Data {
        // The editor colors text with the dynamic system text color. Writing it out would
        // bake in black or white, so leave color off and let the reader apply its default.
        let copy = NSMutableAttributedString(attributedString: content)
        let full = NSRange(location: 0, length: copy.length)
        copy.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if let color = value as? NSColor, color == NSColor.textColor {
                copy.removeAttribute(.foregroundColor, range: range)
            }
        }
        return try copy.data(
            from: full,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// RTF stores the system font as Helvetica Neue and drops dynamic colors. Map both back
    /// so a saved note reopens looking exactly like it did in the editor.
    private static func normalizedAfterRTFRead(_ raw: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: raw)
        let full = NSRange(location: 0, length: result.length)
        let fm = NSFontManager.shared

        result.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let font = value as? NSFont else {
                result.addAttribute(.font, value: NSFont.systemFont(ofSize: NoteSession.defaultFontSize), range: range)
                return
            }
            let family = font.familyName ?? ""
            guard family == "Helvetica Neue" || font.fontName.hasPrefix(".AppleSystemUIFont") else { return }
            let traits = font.fontDescriptor.symbolicTraits
            var system = NSFont.systemFont(ofSize: font.pointSize)
            if traits.contains(.bold) { system = fm.convert(system, toHaveTrait: .boldFontMask) }
            if traits.contains(.italic) { system = fm.convert(system, toHaveTrait: .italicFontMask) }
            result.addAttribute(.font, value: system, range: range)
        }

        result.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if value == nil {
                result.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            }
        }
        return result
    }
}

/// Where untitled and renamed notes land on disk.
enum AutoSaveManager {
    static var desktopDirectory: URL? {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    static func sanitizedFileName(_ title: String?) -> String? {
        guard let title else { return nil }
        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !cleaned.isEmpty, cleaned != "Untitled", !cleaned.hasPrefix(".") else { return nil }
        return cleaned
    }

    static func timestampFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    /// A URL in `directory` that doesn't exist yet: "Notes.txt", then "Notes 2.txt", "Notes 3.txt"…
    /// `ignoring` lets a file keep its own name when it is being renamed in place.
    static func uniqueURL(in directory: URL, baseName: String, ext: String, ignoring: URL? = nil) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: candidate.path), candidate.standardizedFileURL != ignoring?.standardizedFileURL {
            candidate = directory.appendingPathComponent("\(baseName) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}

/// Remembers open tabs between launches, in ~/Library/Application Support/Blankr.
/// Each tab's content is snapshotted with keyed archiving (lossless, unlike RTF), and the
/// snapshot is only preferred over the real file when that file hasn't changed since.
enum SessionStore {
    struct TabRecord: Codable {
        var id: UUID
        var customTitle: String?
        var filePath: String?
        var ownsFile: Bool
        var isDirty: Bool
        var fileModificationDate: Date?
        var isEditing: Bool?
        var wrapsLines: Bool?
    }

    struct Session: Codable {
        var tabs: [TabRecord]
        var selectedTabId: UUID?
    }

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Blankr", isDirectory: true)
    }

    private static var sessionURL: URL? { directory?.appendingPathComponent("session.json") }
    private static var snapshotsDirectory: URL? { directory?.appendingPathComponent("Snapshots", isDirectory: true) }

    private static func snapshotURL(for id: UUID) -> URL? {
        snapshotsDirectory?.appendingPathComponent(id.uuidString + ".archive")
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func save(tabs: [EditorTab], selectedTabId: UUID) {
        guard let sessionURL, let snapshotsDirectory else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)

        var records: [TabRecord] = []
        for tab in tabs {
            if let url = snapshotURL(for: tab.id),
               let data = try? NSKeyedArchiver.archivedData(withRootObject: tab.content, requiringSecureCoding: true) {
                try? data.write(to: url, options: .atomic)
            }
            records.append(TabRecord(
                id: tab.id,
                customTitle: tab.customTitle,
                filePath: tab.fileURL?.path,
                ownsFile: tab.ownsFile,
                isDirty: tab.isDirty,
                fileModificationDate: tab.fileURL.flatMap(modificationDate(of:)),
                isEditing: tab.isEditing,
                wrapsLines: tab.wrapsLines
            ))
        }

        let session = Session(tabs: records, selectedTabId: selectedTabId)
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: sessionURL, options: .atomic)
        }

        // Drop snapshots of tabs that are gone.
        let keep = Set(tabs.map { $0.id.uuidString + ".archive" })
        for name in (try? fm.contentsOfDirectory(atPath: snapshotsDirectory.path)) ?? [] where !keep.contains(name) {
            try? fm.removeItem(at: snapshotsDirectory.appendingPathComponent(name))
        }
    }

    static func load() -> (tabs: [EditorTab], selectedTabId: UUID?)? {
        guard let sessionURL,
              let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(Session.self, from: data) else { return nil }

        var tabs: [EditorTab] = []
        for record in session.tabs {
            let snapshot = snapshotURL(for: record.id)
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: $0) }

            var tab = EditorTab(id: record.id, customTitle: record.customTitle)

            if let path = record.filePath {
                let url = URL(fileURLWithPath: path)
                // The file was deleted or moved outside Blankr: respect that and drop the tab.
                guard FileManager.default.fileExists(atPath: path) else { continue }
                tab.fileURL = url
                tab.ownsFile = record.ownsFile

                var unchangedOnDisk = false
                if let recorded = record.fileModificationDate, let current = modificationDate(of: url) {
                    unchangedOnDisk = abs(current.timeIntervalSince(recorded)) < 0.001
                }
                let content: NSAttributedString
                if unchangedOnDisk, let snapshot {
                    content = snapshot
                    tab.isDirty = record.isDirty
                } else if let fromDisk = try? DocumentIO.read(url: url) {
                    content = fromDisk
                } else {
                    continue
                }
                let styled = EditorTab.forFile(url, content: content, id: record.id)
                tab.content = styled.content
                tab.kind = styled.kind
                tab.isEditing = record.isEditing ?? false
                tab.wrapsLines = record.wrapsLines ?? styled.wrapsLines
            } else {
                tab.content = snapshot ?? NSAttributedString()
                tab.isDirty = record.isDirty
            }
            tabs.append(tab)
        }
        return (tabs, session.selectedTabId)
    }
}
