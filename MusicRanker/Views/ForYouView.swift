import SwiftUI

struct ForYouView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var selectedTrack: iTunesTrack?

    var body: some View {
        Group {
            if engine.isLoadingForYou && engine.forYouSections.isEmpty {
                loadingState
            } else if engine.forYouSections.isEmpty {
                emptyState
            } else {
                sectionsContent
            }
        }
        .task { await engine.loadForYou() }
        .sheet(item: $selectedTrack) { track in
            TrackDetailView(track: track)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var sectionsContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(engine.forYouSections) { section in
                    ForYouSectionView(
                        section: section,
                        onTrackSelected: { track in
                            selectedTrack = track
                        }
                    )
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .refreshable { await engine.refreshForYou() }
    }

    // MARK: - Loading

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

    // MARK: - Empty

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
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            sectionHeader
                .padding(.horizontal, 20)

            // Horizontal track cards
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
                                    Task { player.forcePlay(track: track) }
                                }
                            }
                        )
                        .contextMenu {
                            // Like
                            Button {
                                HapticManager.notification(.success)
                                engine.saveFeedback(track: track, liked: true)
                            } label: {
                                Label("J'aime", systemImage: engine.isTrackLiked(id: track.id) ? "heart.fill" : "heart")
                            }

                            // Dislike
                            Button(role: .destructive) {
                                HapticManager.notification(.warning)
                                engine.saveFeedback(track: track, liked: false)
                            } label: {
                                Label("Pas pour moi", systemImage: "hand.thumbsdown")
                            }

                            Divider()

                            // Play
                            Button {
                                HapticManager.impact(.light)
                                player.forcePlay(track: track)
                            } label: {
                                Label("Écouter", systemImage: "play.fill")
                            }

                            // Details
                            Button {
                                onTrackSelected(track)
                            } label: {
                                Label("Détails", systemImage: "info.circle")
                            }
                        } preview: {
                            // Context menu preview card
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
            // Artwork with play indicator
            ZStack(alignment: .bottomTrailing) {
                AsyncArtwork(url: track.artworkURL(size: 300), size: 150, radius: 14)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                // Play indicator
                if isPlaying {
                    playingIndicator
                }
            }
            .onTapGesture { onTap() }

            // Track info
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
