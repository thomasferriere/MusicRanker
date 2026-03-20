import SwiftUI

/// Detailed track view — Apple Music-inspired immersive layout
struct TrackDetailView: View {
    let track: iTunesTrack
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var gradientColors: [Color] = ColorExtractor.fallbackColors

    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: gradientColors + [Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Large artwork
                    artworkSection
                        .padding(.top, 24)

                    // Title & Artist
                    headerSection
                        .padding(.top, 20)

                    // Play button
                    playButton
                        .padding(.top, 20)

                    // Metadata
                    metadataSection
                        .padding(.top, 28)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .task {
            let colors = await ColorExtractor.shared.extractColors(from: track.artworkURL(size: 100))
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientColors = colors
            }
        }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        AsyncArtwork(url: track.artworkURL(size: 600), size: 280, radius: 20)
            .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text(track.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(track.artistName)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let album = track.albumName {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Play Button

    private var playButton: some View {
        Button {
            HapticManager.impact(.light)
            if player.isCurrent(id: track.id) {
                player.togglePause()
            } else {
                Task { await player.forcePlay(track: track) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(isPlaying ? "Pause" : "Écouter l'extrait")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.tint, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 0) {
            if let album = track.albumName {
                metadataRow(label: "Album", value: album, icon: "square.stack")
            }

            if let genre = track.genre {
                metadataRow(label: "Genre", value: genre, icon: "guitars")
            }

            if let date = track.formattedReleaseDate {
                metadataRow(label: "Date de sortie", value: date, icon: "calendar")
            }

            if let duration = track.formattedDuration {
                metadataRow(label: "Durée", value: duration, icon: "clock")
            }

            if let trackNum = track.trackNumber {
                metadataRow(label: "Piste", value: "#\(trackNum)", icon: "number")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metadataRow(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 12)

            Divider()
                .opacity(0.5)
        }
    }
}
