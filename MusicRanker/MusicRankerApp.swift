import SwiftUI

@main
struct VibelyApp: App {
    let persistence = PersistenceController.shared
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var engine: RecommendationEngine
    @StateObject private var playlistManager: PlaylistManager
    @StateObject private var trendingService = TrendingService()
    @StateObject private var moodManager = MoodManager()

    init() {
        let context = PersistenceController.shared.container.viewContext
        _engine = StateObject(wrappedValue: RecommendationEngine(context: context))
        _playlistManager = StateObject(wrappedValue: PlaylistManager(context: context))

        // Global appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(player)
                .environmentObject(engine)
                .environmentObject(playlistManager)
                .environmentObject(trendingService)
                .environmentObject(moodManager)
                .preferredColorScheme(.dark)
        }
    }
}
