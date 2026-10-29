import SwiftUI

@main
struct NOMADApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            MapsView()
                .tabItem { Label("Maps", systemImage: "map") }
            NotesView()
                .tabItem { Label("Notes", systemImage: "note.text") }
            CyberChefView()
                .tabItem { Label("Data Tools", systemImage: "wrench.and.screwdriver") }
        }
    }
}
