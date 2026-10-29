import Foundation
import UniformTypeIdentifiers

/// On-device folders. They sit in the app's Documents directory, which the Files app shows under
/// On My iPad > NOMAD, so large ZIM and map files can be copied in without going through the app.
enum Storage {
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let zim = folder("ZIM")
    static let maps = folder("Maps")
    static let notes = folder("Notes")

    static let zimType = UTType(importedAs: "org.openzim.zim")
    static let pmtilesType = UTType(importedAs: "com.protomaps.pmtiles")

    private static func folder(_ name: String) -> URL {
        let url = documents.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func files(in folder: URL, withExtension ext: String) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == ext }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Copies a file picked in the document picker into one of the app folders, replacing any file of the same name.
    static func importFile(_ source: URL, into folder: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func displaySize(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
