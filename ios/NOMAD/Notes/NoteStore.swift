import Foundation

struct Note: Identifiable, Hashable {
    let url: URL
    let modified: Date

    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

/// Notes are plain Markdown files in Documents/Notes, the same format FlatNotes uses on the NOMAD server,
/// so a notes folder can be copied between the two.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []

    private let folder = Storage.notes
    private let fileManager = FileManager.default

    func reload() {
        notes = Storage.files(in: folder, withExtension: "md")
            .map { Note(url: $0, modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.modified > $1.modified }
    }

    func create() -> URL {
        var name = "Untitled"
        var counter = 2
        while fileManager.fileExists(atPath: fileURL(for: name).path) {
            name = "Untitled \(counter)"
            counter += 1
        }
        let url = fileURL(for: name)
        try? Data().write(to: url)
        reload()
        return url
    }

    func text(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Writes only to a note that still exists, so a late save from a closing editor cannot recreate a deleted note.
    func save(_ text: String, to url: URL) {
        guard fileManager.fileExists(atPath: url.path), text != self.text(of: url) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Renames the file to match a new title. Returns the new URL, or the old one if the title is unusable or taken.
    func rename(_ url: URL, to title: String) -> URL {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let target = fileURL(for: cleaned)
        guard !cleaned.isEmpty, !cleaned.hasPrefix("."), target != url,
              !fileManager.fileExists(atPath: target.path),
              (try? fileManager.moveItem(at: url, to: target)) != nil else { return url }
        reload()
        return target
    }

    func delete(_ url: URL) {
        try? fileManager.removeItem(at: url)
        reload()
    }

    private func fileURL(for title: String) -> URL {
        folder.appendingPathComponent(title).appendingPathExtension("md")
    }
}
