import SwiftUI
import ZimKit

struct LibraryView: View {
    var body: some View {
        FileLibraryView(
            title: "Library",
            folder: Storage.zim,
            fileExtension: "zim",
            contentType: Storage.zimType,
            emptyMessage: "Import a ZIM file (Wikipedia, medical references, books) from download.kiwix.org, or copy it in the Files app to On My iPad > NOMAD > ZIM.",
            displayName: { (try? ZimArchive(url: $0))?.title }
        ) { files in
            ZimReaderView(fileURL: files[0])
        }
    }
}
