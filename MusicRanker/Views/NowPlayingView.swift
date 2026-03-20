import SwiftUI

/// Full-screen Now Playing view — Apple Music inspired
struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @Environment(\.dismiss) private var dismiss

    @State private var gradientColors: [Color] = ColorExtractor.fallbackColors
    @State private var liked = false
    @State private var disliked = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: gradientColors + [Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator + close
                header
                    .padding(.top, 12)

                Spacer(minLength: 20)

                // Artwork
                artwork

                Spacer(minLength: 24)

                // Track info
                trackInfo

                // Progress
                progressSection
                    .padding(.top, 20)

                // Controls
                playbackControls
                    .padding(.top, 24)

                // Like / Dislike
                feedbackButtons
                    .padding(.top, 28)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 32)
        }
        .task { await loadColors() }
        .onChange(of: player.currentTrack?.id) { _, _ in
            Task { await loadColors() }
            updateLikeState()
        }
        .onAppear { updateLikeState() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 5)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text("En écoute")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                // Balance spacer
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .opacity(0)
            }
        }
    }

    // MARK: - Artwork

    private var artwork: some View {
        Group {
            if let track = player.currentTrack {
                AsyncArtwork(url: track.artworkURL(size: 600), size: 300, radius: 16)
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                    .frame(width: 300, height: 300)
            }
        }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(player.currentTrack?.title ?? "—")
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text(player.currentTrack?.artistName ?? "—")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))

            if let album = player.currentTrack?.albumName {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(.white.opacity(0.7))
                        .frame(width: max(0, geo.size.width * player.progress), height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text(formatTime(player.progress * 30))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(player.currentTrack?.formattedDuration ?? "0:30")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        Button {
            HapticManager.impact(.light)
            player.togglePause()
        } label: {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feedback

    private var feedbackButtons: some View {
        HStack(spacing: 48) {
            Button {
                guard let track = player.currentTrack else { return }
                HapticManager.notification(.warning)
                withAnimation(.spring(duration: 0.3)) { disliked = true; liked = false }
                engine.saveFeedback(track: track, liked: false)
            } label: {
                Image(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.title2)
                    .foregroundStyle(disliked ? .red : .white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Button {
                guard let track = player.currentTrack else { return }
                HapticManager.notification(.success)
                withAnimation(.spring(duration: 0.3)) { liked = true; disliked = false }
                engine.saveFeedback(track: track, liked: true)
            } label: {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(liked ? .pink : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func loadColors() async {
        guard let url = player.currentTrack?.artworkURL(size: 100) else { return }
        let colors = await ColorExtractor.shared.extractColors(from: url)
        withAnimation(.easeInOut(duration: 0.5)) {
            gradientColors = colors
        }
    }

    private func updateLikeState() {
        guard let id = player.currentTrack?.id else { return }
        liked = engine.isTrackLiked(id: id)
        disliked = false
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
