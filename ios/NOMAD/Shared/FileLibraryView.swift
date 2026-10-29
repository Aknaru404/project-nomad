import SwiftUI
import UniformTypeIdentifiers

/// List of the files in one app folder, with import from the Files app, swipe-to-delete and a viewer per file.
struct FileLibraryView<Destination: View>: View {
    let title: String
    let folder: URL
    let fileExtension: String
    let contentType: UTType
    let emptyMessage: String
    /// Display name for a file, computed once per reload (opening a ZIM header is cheap but not free).
    var displayName: (URL) -> String? = { _ in nil }
    var openAllLabel: String?
    @ViewBuilder let destination: ([URL]) -> Destination

    @State private var files: [URL] = []
    @State private var names: [URL: String] = [:]
    @State private var importing = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var pendingDelete: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView {
                        Label("No \(fileExtension.uppercased()) files yet", systemImage: "tray")
                    } description: {
                        Text(emptyMessage)
                    } actions: {
                        Button("Import File") { importing = true }
                    }
                } else {
                    List {
                        ForEach(files, id: \.self) { file in
                            NavigationLink(value: file) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(names[file] ?? file.deletingPathExtension().lastPathComponent).font(.headline)
                                    Text("\(file.lastPathComponent) · \(Storage.displaySize(of: file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { pendingDelete = file } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .refreshable { reload() }
                }
            }
            .navigationTitle(title)
            .navigationDestination(for: URL.self) { destination([$0]) }
            .toolbar {
                if let openAllLabel, files.count > 1 {
                    ToolbarItem(placement: .secondaryAction) {
                        NavigationLink(openAllLabel) { destination(files) }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                        .disabled(busy)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [contentType], allowsMultipleSelection: true) {
                importFiles($0)
            }
            .overlay {
                if busy {
                    ProgressView("Copying into NOMAD…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Delete this file?", isPresented: isPresent($pendingDelete), presenting: pendingDelete) { file in
                Button("Delete", role: .destructive) {
                    try? FileManager.default.removeItem(at: file)
                    reload()
                }
            } message: { file in
                Text(file.lastPathComponent)
            }
            .alert("Import failed", isPresented: isPresent($errorMessage), presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
            .onAppear(perform: reload)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reload() }
            }
        }
    }

    private func reload() {
        files = Storage.files(in: folder, withExtension: fileExtension)
        var updated: [URL: String] = [:]
        for file in files { updated[file] = names[file] ?? displayName(file) }
        names = updated
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            busy = true
            let destination = folder
            Task.detached(priority: .userInitiated) {
                var failure: String?
                for url in urls {
                    do { _ = try Storage.importFile(url, into: destination) } catch { failure = error.localizedDescription }
                }
                await MainActor.run {
                    busy = false
                    errorMessage = failure
                    reload()
                }
            }
        }
    }

    private func isPresent<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
