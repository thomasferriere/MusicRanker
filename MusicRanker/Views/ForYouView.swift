import SwiftUI

struct ForYouView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var playlistManager: PlaylistManager

    @State private var selectedTrack: iTunesTrack?
    @State private var playlistTarget: iTunesTrack?

    // Country trends
    @State private var trendingSections: [TrendingSection] = []
    @State private var isLoadingTrends = false

    struct TrendingSection: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let icon: String
        let tracks: [iTunesTrack]
    }

    var body: some View {
        Group {
            if engine.isLoadingForYou && engine.forYouSections.isEmpty {
                loadingState
            } else if engine.forYouSections.isEmpty && trendingSections.isEmpty {
                emptyState
            } else {
                sectionsContent
            }
        }
        .task {
            await engine.loadForYou()
            await loadTrends()
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
                // Country trends
                ForEach(trendingSections) { section in
                    trendingSectionView(section)
                }

                // Personalized sections
                ForEach(engine.forYouSections) { section in
                    ForYouSectionView(
                        section: section,
                        onTrackSelected: { track in selectedTrack = track },
                        onAddToPlaylist: { track in playlistTarget = track }
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .refreshable {
            await engine.refreshForYou()
            await loadTrends()
        }
    }

    // MARK: - Trending Section View

    private func trendingSectionView(_ section: TrendingSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(section.tracks) { track in
                        ForYouTrackCard(track: track) {
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
            HapticManager.impact(.light)
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

        // External platforms
        Menu("Ouvrir dans...") {
            ForEach(MusicPlatform.allCases) { platform in
                Button {
                    ExternalMusicOpener.open(
                        platform: platform,
                        title: track.title,
                        artist: track.artistName
                    )
                } label: {
                    Label(platform.rawValue, systemImage: platform.icon)
                }
            }
        }
    }

    // MARK: - Load Trends

    private func loadTrends() async {
        guard trendingSections.isEmpty else { return }
        isLoadingTrends = true

        let service = iTunesService.shared
        let year = Calendar.current.component(.year, from: Date())

        // Tendances France (based on country=fr in iTunesService)
        let trendTerms = ["top hits france \(year)", "hits français \(year)"]
        var trendTracks: [iTunesTrack] = []
        for term in trendTerms {
            let t = await service.search(term: term, limit: 15)
            trendTracks.append(contentsOf: t)
        }

        // Deduplicate
        var seen: Set<Int> = []
        let uniqueTrends = trendTracks.filter { $0.previewURL != nil && seen.insert($0.id).inserted }.prefix(10)

        var sections: [TrendingSection] = []
        if uniqueTrends.count >= 3 {
            sections.append(TrendingSection(
                title: "Tendances France",
                subtitle: "Les sons du moment 🇫🇷",
                icon: "chart.line.uptrend.xyaxis",
                tracks: Array(uniqueTrends)
            ))
        }

        // Tendances internationales
        let intlTracks = await service.search(term: "top hits \(year) global", limit: 15)
        let uniqueIntl = intlTracks.filter { $0.previewURL != nil && seen.insert($0.id).inserted }.prefix(10)
        if uniqueIntl.count >= 3 {
            sections.append(TrendingSection(
                title: "Tendances Monde",
                subtitle: "Hits internationaux",
                icon: "globe",
                tracks: Array(uniqueIntl)
            ))
        }

        trendingSections = sections
        isLoadingTrends = false
    }

    // MARK: - Loading & Empty

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
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
                                HapticManager.impact(.light)
                                player.forcePlay(track: track)
                            } label: {
                                Label("Écouter", systemImage: "play.fill")
                            }

                            Button {
                                onAddToPlaylist(track)
                            } label: {
                                Label("Ajouter à une playlist", systemImage: "text.badge.plus")
                            }

                            Button {
                                onTrackSelected(track)
                            } label: {
                                Label("Détails", systemImage: "info.circle")
                            }

                            Menu("Ouvrir dans...") {
                                ForEach(MusicPlatform.allCases) { platform in
                                    Button {
                                        ExternalMusicOpener.open(
                                            platform: platform,
                                            title: track.title,
                                            artist: track.artistName
                                        )
                                    } label: {
                                        Label(platform.rawValue, systemImage: platform.icon)
                                    }
                                }
                            }
                        } preview: {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncArtwork(url: track.artworkURL(size: 600), size: 280, radius: 16)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text(track.artistName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let album = track.albumName {
                                        Text(album)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
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
                Text(section.title)
                    .font(.headline)
                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    playingIndicator
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

    private var playingIndicator: some View {
        Image(systemName: "waveform")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            .padding(6)
            .background(.black.opacity(0.5), in: Circle())
            .padding(6)
    }
}
