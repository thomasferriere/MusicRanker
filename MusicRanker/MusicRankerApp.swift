import SwiftUI

@main
struct MusicRankerApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var engine: RecommendationEngine
    @StateObject private var playlistManager: PlaylistManager

    init() {
        let context = PersistenceController.shared.container.viewContext
        _engine = StateObject(wrappedValue: RecommendationEngine(context: context))
        _playlistManager = StateObject(wrappedValue: PlaylistManager(context: context))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(player)
                .environmentObject(engine)
                .environmentObject(playlistManager)
                .preferredColorScheme(.dark)
        }
    }
}
