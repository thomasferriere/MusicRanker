import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var trendingService: TrendingService
    @EnvironmentObject private var moodManager: MoodManager

    @State private var selectedTab = 0
    @State private var showNowPlaying = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Découvrir", systemImage: "sparkles", value: 0) {
                DiscoverView()
            }

            Tab("Recherche", systemImage: "magnifyingglass", value: 1) {
                NavigationStack {
                    SearchView()
                        .navigationTitle("Recherche")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

            Tab("Pour toi", systemImage: "wand.and.stars", value: 2) {
                NavigationStack {
                    ForYouView()
                        .navigationTitle("Pour toi")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

            Tab("Bibliothèque", systemImage: "books.vertical", value: 3) {
                NavigationStack {
                    LibraryView()
                        .navigationTitle("Bibliothèque")
                        .navigationBarTitleDisplayMode(.large)
                }
                .safeAreaInset(edge: .bottom) { miniPlayerBar }
            }

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
                .environmentObject(moodManager)
        }
    }

    // MARK: - Glass Mini Player

    @ViewBuilder
    private var miniPlayerBar: some View {
        if player.currentTrack != nil {
            GlassMiniPlayer(onTap: { showNowPlaying = true })
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: player.currentTrack?.id)
        }
    }
}

// MARK: - Glass Mini Player (premium blur + swipe up)

struct GlassMiniPlayer: View {
    @EnvironmentObject private var player: AudioPlayerManager
    var onTap: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Progress line — glowing
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * player.progress)
                        .shadow(color: .purple.opacity(0.4), radius: 4, y: 0)
                        .animation(.linear(duration: 0.25), value: player.progress)
                }
            }
            .frame(height: 2.5)

            HStack(spacing: 10) {
                if let track = player.currentTrack {
                    // Artwork with subtle rotation when playing
                    AsyncArtwork(
                        url: track.artworkURL(size: 100),
                        size: 40,
                        radius: 8
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
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

                // Play/pause with symbol transition
                Button {
                    HapticManager.impact(.light)
                    player.togglePause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.callout.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 34, height: 34)
                }
                .tint(.primary)

                Button {
                    HapticManager.selection()
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .frame(width: 28, height: 28)
                }
                .tint(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background {
            ZStack {
                // Glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                // Subtle gradient tint
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.04), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height * 0.4
                    }
                }
                .onEnded { value in
                    if value.translation.height < -40 || value.predictedEndTranslation.height < -80 {
                        // Swipe up → open full player
                        withAnimation(.spring(duration: 0.2)) { dragOffset = 0 }
                        onTap()
                    } else {
                        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { dragOffset = 0 }
                    }
                }
        )
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
        .environmentObject(MoodManager())
}
