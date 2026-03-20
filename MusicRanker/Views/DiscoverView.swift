import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var gradientColors: [Color] = ColorExtractor.fallbackColors
    @State private var detailTrack: iTunesTrack?

    var body: some View {
        ZStack {
            // Dynamic gradient background
            dynamicBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if engine.isLoading && engine.cards.isEmpty {
                    loadingState
                } else if engine.cards.isEmpty {
                    emptyState
                } else {
                    cardStack
                }
            }
        }
        .task {
            await engine.loadInitialCards()
            if let first = engine.cards.first {
                player.forcePlay(track: first)
                await updateGradient(for: first)
            }
        }
        .sheet(item: $detailTrack) { track in
            TrackDetailView(track: track)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Dynamic Background

    private var dynamicBackground: some View {
        LinearGradient(
            colors: gradientColors + [Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(.easeInOut(duration: 0.8), value: gradientColors.description)
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        GeometryReader { geo in
            let cardHeight = geo.size.height * 0.72
            let cardWidth = geo.size.width - 40

            VStack(spacing: 0) {
                Spacer(minLength: 16)

                // Stacked cards
                ZStack {
                    ForEach(Array(engine.cards.prefix(3).enumerated().reversed()), id: \.element.id) { index, track in
                        let isTop = index == 0
                        SwipeCard(
                            track: track,
                            isTop: isTop,
                            width: cardWidth,
                            height: cardHeight,
                            onSwipe: { liked in
                                handleSwipe(track: track, liked: liked)
                            },
                            onTapArtwork: {
                                handleArtworkTap(track: track)
                            },
                            onLongPress: {
                                detailTrack = track
                            }
                        )
                        .scaleEffect(isTop ? 1 : 1 - CGFloat(index) * 0.05)
                        .offset(y: isTop ? 0 : CGFloat(index) * 12)
                        .allowsHitTesting(isTop)
                    }
                }

                Spacer(minLength: 12)

                // Action buttons
                actionButtons
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 50) {
            // Dislike
            Button {
                if let track = engine.cards.first {
                    handleSwipe(track: track, liked: false)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                    Circle()
                        .strokeBorder(.red.opacity(0.4), lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Image(systemName: "xmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)

            // Like
            Button {
                if let track = engine.cards.first {
                    handleSwipe(track: track, liked: true)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                    Circle()
                        .strokeBorder(.green.opacity(0.4), lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Image(systemName: "heart.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading & Empty

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(.white)
            Text("Chargement...")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
            Text("Aucun morceau disponible")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text("Vérifie ta connexion et réessaie.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handleSwipe(track: iTunesTrack, liked: Bool) {
        withAnimation(.spring(duration: 0.35)) {
            engine.cards.removeAll { $0.id == track.id }
        }
        engine.cardSwiped(track, liked: liked)
        HapticManager.impact(liked ? .medium : .light)

        // Auto-play next
        if let next = engine.cards.first {
            Task {
                player.forcePlay(track: next)
                await updateGradient(for: next)
            }
        } else {
            player.stop()
        }
    }

    private func handleArtworkTap(track: iTunesTrack) {
        HapticManager.impact(.light)
        if player.isCurrent(id: track.id) {
            player.togglePause()
        } else {
            Task { player.forcePlay(track: track) }
        }
    }

    private func updateGradient(for track: iTunesTrack) async {
        let colors = await ColorExtractor.shared.extractColors(from: track.artworkURL(size: 100))
        withAnimation(.easeInOut(duration: 0.6)) {
            gradientColors = colors
        }
    }
}

// MARK: - Swipe Card

struct SwipeCard: View {
    let track: iTunesTrack
    let isTop: Bool
    let width: CGFloat
    let height: CGFloat
    let onSwipe: (Bool) -> Void
    let onTapArtwork: () -> Void
    let onLongPress: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @State private var offset: CGSize = .zero
    @State private var isPressed = false

    private var swipeProgress: CGFloat { offset.width / 150 }
    private var isPlayingThis: Bool { player.isCurrentlyPlaying(id: track.id) }
    private var isCurrentTrack: Bool { player.isCurrent(id: track.id) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            // Artwork with tap-to-play and long-press-for-info
            artworkView
                .padding(.horizontal, 24)

            Spacer(minLength: 14)

            // Track info
            trackInfo
                .padding(.horizontal, 24)

            // Progress bar
            if isCurrentTrack {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            Spacer(minLength: 16)

            // Swipe hints
            swipeHints
                .padding(.bottom, 12)
        }
        .frame(width: width, height: height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(swipeBorderColor, lineWidth: 2.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        .offset(x: offset.width, y: offset.height * 0.3)
        .rotationEffect(.degrees(Double(offset.width) / 25))
        .gesture(swipeGesture)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkView: some View {
        let artworkSize = min(width - 48, height * 0.50)

        ZStack {
            AsyncArtwork(url: track.artworkURL(size: 600), size: artworkSize, radius: 20)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                .scaleEffect(isPressed ? 0.95 : 1)
                .animation(.spring(duration: 0.2), value: isPressed)

            // Play/Pause overlay
            if isCurrentTrack {
                Circle()
                    .fill(.black.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .opacity(isPlayingThis ? 0 : 0.8)
            }
        }
        .onTapGesture {
            onTapArtwork()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            HapticManager.impact(.medium)
            onLongPress()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(track.title)
                .font(.title3.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(track.artistName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let genre = track.genre {
                    genreTag(genre)
                }
                if let year = track.releaseYear {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 2)
        }
    }

    private func genreTag(_ genre: String) -> some View {
        Text(genre)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.1), in: Capsule())
            .foregroundStyle(.secondary)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: 3)
                Capsule()
                    .fill(.white.opacity(0.6))
                    .frame(width: geo.size.width * player.progress, height: 3)
                    .animation(.linear(duration: 0.25), value: player.progress)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Swipe Hints

    private var swipeHints: some View {
        HStack(spacing: 40) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red.opacity(0.25 + max(0, -swipeProgress) * 0.75))

            Image(systemName: "heart.circle.fill")
                .font(.title2)
                .foregroundStyle(.green.opacity(0.25 + max(0, swipeProgress) * 0.75))
        }
    }

    // MARK: - Swipe

    private var swipeBorderColor: Color {
        if swipeProgress > 0.3 { return .green.opacity(0.5) }
        if swipeProgress < -0.3 { return .red.opacity(0.5) }
        return .clear
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 120
                if value.translation.width > threshold {
                    animateOff(direction: 1)
                    onSwipe(true)
                } else if value.translation.width < -threshold {
                    animateOff(direction: -1)
                    onSwipe(false)
                } else {
                    withAnimation(.spring(duration: 0.3)) {
                        offset = .zero
                    }
                }
            }
    }

    private func animateOff(direction: CGFloat) {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: direction * 500, height: 0)
        }
    }
}

// MARK: - Reusable Async Artwork

struct AsyncArtwork: View {
    let url: URL?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    default:
                        placeholder
                            .overlay {
                                ProgressView()
                                    .tint(.secondary)
                            }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.25))
                    .foregroundStyle(.secondary)
            }
    }
}
