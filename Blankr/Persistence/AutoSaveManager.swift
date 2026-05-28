import Foundation

enum AutoSaveManager {
    static func saveIfNeeded(text: String, openedFileURL: URL?, preferredTitle: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url: URL
        if let existing = openedFileURL {
            url = existing
        } else {
            guard let desktop = FileManager.default.urls(
                for: .desktopDirectory,
                in: .userDomainMask
            ).first else { return }
            let cleanedTitle = preferredTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")

            if let cleanedTitle, !cleanedTitle.isEmpty, cleanedTitle != "Untitled" {
                url = desktop.appendingPathComponent(cleanedTitle + ".txt")
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let filename = formatter.string(from: Date()) + ".txt"
                url = desktop.appendingPathComponent(filename)
            }
        }

        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
