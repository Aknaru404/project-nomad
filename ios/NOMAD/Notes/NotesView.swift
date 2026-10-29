import SwiftUI

struct NotesView: View {
    @StateObject private var store = NoteStore()
    @State private var selection: URL?
    @State private var query = ""

    private var filtered: [Note] {
        guard !query.isEmpty else { return store.notes }
        return store.notes.filter {
            $0.title.localizedCaseInsensitiveContains(query) || store.text(of: $0.url).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filtered) { note in
                    NavigationLink(value: note.url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.headline)
                            Text(note.modified, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            if selection == note.url { selection = nil }
                            store.delete(note.url)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if store.notes.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "note.text", description: Text("Notes are saved on this iPad as Markdown files."))
                }
            }
            .searchable(text: $query)
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { selection = store.create() } label: { Label("New Note", systemImage: "square.and.pencil") }
                }
            }
        } detail: {
            if let url = selection {
                NoteEditor(store: store, fileURL: url, selection: $selection)
                    .id(url)
            } else {
                ContentUnavailableView("Select a note", systemImage: "note.text")
            }
        }
        .onAppear(perform: store.reload)
    }
}

struct NoteEditor: View {
    @ObservedObject var store: NoteStore
    @State var fileURL: URL
    @Binding var selection: URL?
    @State private var title = ""
    @State private var text = ""
    @State private var loaded = false
    @State private var previewing = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.title2.bold())
                .padding()
                .onSubmit(commitTitle)
            Divider()
            if previewing {
                ScrollView {
                    Text(rendered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal, 12)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $previewing) { Label("Preview", systemImage: "eye") }
            }
        }
        .onAppear {
            title = fileURL.deletingPathExtension().lastPathComponent
            text = store.text(of: fileURL)
            loaded = true
        }
        .task(id: text) {
            // Autosave shortly after typing stops.
            try? await Task.sleep(for: .milliseconds(500))
            if loaded && !Task.isCancelled { store.save(text, to: fileURL) }
        }
        .onDisappear {
            store.save(text, to: fileURL)
            commitTitle()
        }
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func commitTitle() {
        store.save(text, to: fileURL)
        let renamed = store.rename(fileURL, to: title)
        if renamed != fileURL {
            fileURL = renamed
            if selection != nil { selection = renamed }
        } else {
            title = fileURL.deletingPathExtension().lastPathComponent
        }
    }
}
