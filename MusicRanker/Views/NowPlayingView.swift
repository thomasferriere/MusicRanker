import SwiftUI

/// Full-screen Now Playing view — Apple Music inspired
/// Swipe down to dismiss, long press for platform links, video button
struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var playlistManager: PlaylistManager
    @Environment(\.dismiss) private var dismiss

    @State private var gradientColors: [Color] = ColorExtractor.fallbackColors
    @State private var liked = false
    @State private var disliked = false
    @State private var showPlatforms = false
    @State private var showVideo = false
    @State private var showPlaylistPicker = false
    @State private var dragOffset: CGFloat = 0

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

                Spacer(minLength: 16)

                // Artwork
                artwork

                Spacer(minLength: 20)

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
                    .padding(.top, 20)

                // Bottom actions (video, playlist, platforms)
                bottomActions
                    .padding(.top, 16)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 32)
        }
        .offset(y: dragOffset)
        .gesture(dismissGesture)
        .task { await loadColors() }
        .onChange(of: player.currentTrack?.id) { _, _ in
            Task { await loadColors() }
            updateLikeState()
        }
        .onAppear { updateLikeState() }
        .confirmationDialog("Ouvrir dans...", isPresented: $showPlatforms) {
            ForEach(MusicPlatform.allCases) { platform in
                Button(platform.rawValue) {
                    guard let track = player.currentTrack else { return }
                    ExternalMusicOpener.open(
                        platform: platform,
                        title: track.title,
                        artist: track.artistName
                    )
                }
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showVideo) {
            if let track = player.currentTrack {
                VideoPlayerView(title: track.title, artist: track.artistName)
                    .environmentObject(player)
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            if let track = player.currentTrack {
                AddToPlaylistSheet(track: track)
                    .environmentObject(playlistManager)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Swipe-to-Dismiss Gesture

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 150 || value.predictedEndTranslation.height > 300 {
                    // Dismiss
                    withAnimation(.easeOut(duration: 0.25)) {
                        dragOffset = 1000
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        dismiss()
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        dragOffset = 0
                    }
                }
            }
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
                // Long press for platforms
                Button {
                    showPlatforms = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
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
                    .fill(.gray.opacity(0.15))
                    .frame(width: 300, height: 300)
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            HapticManager.impact(.medium)
            showPlatforms = true
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

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack(spacing: 36) {
            // Video button
            Button {
                HapticManager.impact(.light)
                showVideo = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.callout)
                    Text("Vidéo")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Playlist button
            Button {
                HapticManager.impact(.light)
                showPlaylistPicker = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "text.badge.plus")
                        .font(.callout)
                    Text("Playlist")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            // External platforms
            Button {
                HapticManager.impact(.light)
                showPlatforms = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.callout)
                    Text("Ouvrir dans")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
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
