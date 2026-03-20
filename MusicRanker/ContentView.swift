import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Discover — NO mini player here (user request)
            Tab("Découvrir", systemImage: "sparkles", value: 0) {
                NavigationStack {
                    DiscoverView()
                        .navigationTitle("Découvrir")
                        .navigationBarTitleDisplayMode(.large)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                }
            }

            // Pour toi — with mini player
            Tab("Pour toi", systemImage: "wand.and.stars", value: 1) {
                NavigationStack {
                    ForYouView()
                        .navigationTitle("Pour toi")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

            // Likes — with mini player
            Tab("Likes", systemImage: "heart.fill", value: 2) {
                NavigationStack {
                    LikedSongsView()
                        .navigationTitle("Mes likes")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

            // Profil — with mini player
            Tab("Profil", systemImage: "person.crop.circle", value: 3) {
                NavigationStack {
                    TasteProfileView()
                        .navigationTitle("Mon profil")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }
        }
    }

    // MARK: - Mini Player (only outside Discover)

    @ViewBuilder
    private var miniPlayerBar: some View {
        if player.currentTrack != nil {
            MiniPlayerView()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: player.currentTrack?.id)
        }
    }
}

// MARK: - Mini Player

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            GeometryReader { geo in
                Rectangle()
                    .fill(.tint.opacity(0.6))
                    .frame(width: geo.size.width * player.progress, height: 2)
                    .animation(.linear(duration: 0.25), value: player.progress)
            }
            .frame(height: 2)

            HStack(spacing: 10) {
                if let track = player.currentTrack {
                    AsyncArtwork(
                        url: track.artworkURL(size: 120),
                        size: 42,
                        radius: 8
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
                        .frame(width: 36, height: 36)
                }
                .tint(.primary)

                Button { player.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .frame(width: 36, height: 36)
                }
                .tint(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AudioPlayerManager())
        .environmentObject(RecommendationEngine(context: PersistenceController.preview.container.viewContext))
}
