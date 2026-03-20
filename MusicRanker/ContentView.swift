import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var trendingService: TrendingService

    @State private var selectedTab = 0
    @State private var showNowPlaying = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Discover — NO mini player (immersive)
            Tab("Découvrir", systemImage: "sparkles", value: 0) {
                DiscoverView()
            }

            // Search
            Tab("Recherche", systemImage: "magnifyingglass", value: 1) {
                NavigationStack {
                    SearchView()
                        .navigationTitle("Recherche")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

            // Pour toi
            Tab("Pour toi", systemImage: "wand.and.stars", value: 2) {
                NavigationStack {
                    ForYouView()
                        .navigationTitle("Pour toi")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

            // Bibliothèque (Likes + Playlists)
            Tab("Bibliothèque", systemImage: "books.vertical", value: 3) {
                NavigationStack {
                    LibraryView()
                        .navigationTitle("Bibliothèque")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

            // Profil
            Tab("Profil", systemImage: "person.crop.circle", value: 4) {
                NavigationStack {
                    TasteProfileView()
                        .navigationTitle("Mon profil")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(player)
                .environmentObject(engine)
                .environmentObject(playlistManager)
                .environmentObject(trendingService)
        }
    }

    // MARK: - Mini Player (compact)

    @ViewBuilder
    private var miniPlayerBar: some View {
        if player.currentTrack != nil {
            MiniPlayerView(onTap: { showNowPlaying = true })
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: player.currentTrack?.id)
        }
    }
}

// MARK: - Compact Mini Player

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Ultra-thin progress line
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                    Rectangle()
                        .fill(.tint)
                        .frame(width: geo.size.width * player.progress)
                        .animation(.linear(duration: 0.25), value: player.progress)
                }
            }
            .frame(height: 2)

            HStack(spacing: 10) {
                if let track = player.currentTrack {
                    AsyncArtwork(
                        url: track.artworkURL(size: 100),
                        size: 36,
                        radius: 7
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { player.togglePause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.callout.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                }
                .tint(.primary)

                Button { player.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .frame(width: 28, height: 28)
                }
                .tint(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AudioPlayerManager())
        .environmentObject(RecommendationEngine(context: PersistenceController.preview.container.viewContext))
        .environmentObject(PlaylistManager(context: PersistenceController.preview.container.viewContext))
        .environmentObject(TrendingService())
}
