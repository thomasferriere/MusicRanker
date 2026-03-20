import SwiftUI

struct ForYouView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var trendingService: TrendingService

    @State private var selectedTrack: iTunesTrack?
    @State private var playlistTarget: iTunesTrack?

    var body: some View {
        Group {
            if engine.isLoadingForYou && engine.forYouSections.isEmpty && trendingService.state == .loading {
                loadingState
            } else if engine.forYouSections.isEmpty && trendingService.trendingTracks.isEmpty {
                emptyState
            } else {
                sectionsContent
            }
        }
        .task {
            async let loadForYou: () = engine.loadForYou()
            async let loadTrends: () = trendingService.loadTrending()
            _ = await (loadForYou, loadTrends)
        }
        .sheet(item: $selectedTrack) { track in
            TrackDetailView(track: track)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $playlistTarget) { track in
            AddToPlaylistSheet(track: track)
                .environmentObject(playlistManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var sectionsContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 32) {
                // Real trending section
                if !trendingService.trendingTracks.isEmpty {
                    trendingSection
                }

                // Trending error/loading state
                if trendingService.state == .loading {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.8)
                        Text("Chargement des tendances...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                }

                // Personalized sections
                ForEach(engine.forYouSections) { section in
                    ForYouSectionView(
                        section: section,
                        onTrackSelected: { selectedTrack = $0 },
                        onAddToPlaylist: { playlistTarget = $0 }
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .refreshable {
            async let refreshForYou: () = engine.refreshForYou()
            async let refreshTrends: () = trendingService.refresh()
            _ = await (refreshForYou, refreshTrends)
        }
    }

    // MARK: - Real Trending Section

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with country
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Tendances")
                            .font(.headline)
                        Text(countryFlag(trendingService.countryCode))
                            .font(.callout)
                    }
                    Text("En ce moment \(trendingService.countryName.hasPrefix("à") || trendingService.countryName.hasPrefix("en") ? trendingService.countryName : "en \(trendingService.countryName)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Source badge
                Text(trendingService.sourceName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 20)

            // Tracks
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(trendingService.trendingTracks.prefix(15).enumerated()), id: \.element.id) { index, track in
                        TrendingTrackCard(track: track, rank: index + 1) {
                            HapticManager.impact(.light)
                            if player.isCurrent(id: track.id) {
                                player.togglePause()
                            } else {
                                player.forcePlay(track: track)
                            }
                        }
                        .contextMenu {
                            trackContextMenu(track: track)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func trackContextMenu(track: iTunesTrack) -> some View {
        Button {
            HapticManager.notification(.success)
            engine.saveFeedback(track: track, liked: true)
        } label: {
            Label(
                engine.isTrackLiked(id: track.id) ? "Déjà liké" : "J'aime",
                systemImage: engine.isTrackLiked(id: track.id) ? "heart.fill" : "heart"
            )
        }

        Button(role: .destructive) {
            HapticManager.notification(.warning)
            engine.saveFeedback(track: track, liked: false)
        } label: {
            Label("Pas pour moi", systemImage: "hand.thumbsdown")
        }

        Divider()

        Button {
            player.forcePlay(track: track)
        } label: {
            Label("Écouter", systemImage: "play.fill")
        }

        Button {
            playlistTarget = track
        } label: {
            Label("Ajouter à une playlist", systemImage: "text.badge.plus")
        }

        Button {
            selectedTrack = track
        } label: {
            Label("Détails", systemImage: "info.circle")
        }

        Menu("Ouvrir dans...") {
            ForEach(MusicPlatform.allCases) { platform in
                Button {
                    ExternalMusicOpener.open(platform: platform, title: track.title, artist: track.artistName)
                } label: {
                    Label(platform.rawValue, systemImage: platform.icon)
                }
            }
        }
    }

    // MARK: - Helpers

    private func countryFlag(_ code: String) -> String {
        let base: UInt32 = 127397
        return code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(base + $0.value) }
            .map { String($0) }
            .joined()
    }

    // MARK: - Loading & Empty

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.2)
            Text("Analyse de tes goûts...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Pas encore de suggestions")
                .font(.title3.weight(.semibold))
            Text("Swipe quelques morceaux dans Découvrir pour que l'IA apprenne tes goûts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Trending Track Card (with rank badge)

struct TrendingTrackCard: View {
    let track: iTunesTrack
    let rank: Int
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncArtwork(url: track.artworkURL(size: 300), size: 150, radius: 14)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(6)
                    }
                }

                // Rank badge
                Text("#\(rank)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(6)
            }
            .onTapGesture { onTap() }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(track.artistName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

// MARK: - Section View

struct ForYouSectionView: View {
    let section: RecommendationEngine.ForYouSection
    let onTrackSelected: (iTunesTrack) -> Void
    let onAddToPlaylist: (iTunesTrack) -> Void
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(section.tracks) { track in
                        ForYouTrackCard(
                            track: track,
                            onTap: {
                                HapticManager.impact(.light)
                                if player.isCurrent(id: track.id) {
                                    player.togglePause()
                                } else {
                                    player.forcePlay(track: track)
                                }
                            }
                        )
                        .contextMenu {
                            Button {
                                HapticManager.notification(.success)
                                engine.saveFeedback(track: track, liked: true)
                            } label: {
                                Label(engine.isTrackLiked(id: track.id) ? "Déjà liké" : "J'aime", systemImage: engine.isTrackLiked(id: track.id) ? "heart.fill" : "heart")
                            }

                            Button(role: .destructive) {
                                HapticManager.notification(.warning)
                                engine.saveFeedback(track: track, liked: false)
                            } label: {
                                Label("Pas pour moi", systemImage: "hand.thumbsdown")
                            }

                            Divider()

                            Button { player.forcePlay(track: track) } label: {
                                Label("Écouter", systemImage: "play.fill")
                            }

                            Button { onAddToPlaylist(track) } label: {
                                Label("Ajouter à une playlist", systemImage: "text.badge.plus")
                            }

                            Button { onTrackSelected(track) } label: {
                                Label("Détails", systemImage: "info.circle")
                            }
                        } preview: {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncArtwork(url: track.artworkURL(size: 600), size: 280, radius: 16)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.headline).lineLimit(2)
                                    Text(track.artistName).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)
                            }
                            .padding(12)
                            .frame(width: 304)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.headline)
                if let subtitle = section.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Track Card

struct ForYouTrackCard: View {
    let track: iTunesTrack
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                AsyncArtwork(url: track.artworkURL(size: 300), size: 150, radius: 14)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                        .padding(6)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(6)
                }
            }
            .onTapGesture { onTap() }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(track.artistName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}
