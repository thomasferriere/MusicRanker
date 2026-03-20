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

            if engine.isLoading && engine.cards.isEmpty {
                loadingState
            } else if engine.cards.isEmpty {
                emptyState
            } else {
                cardContent
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

    // MARK: - Card Content

    private var cardContent: some View {
        GeometryReader { geo in
            let safeWidth = geo.size.width
            let safeHeight = geo.size.height

            // Card dimensions — leave room for buttons + tab bar
            let cardWidth = safeWidth - 48
            let buttonsHeight: CGFloat = 80  // buttons area
            let topPadding: CGFloat = 8
            let spacing: CGFloat = 20
            let cardHeight = safeHeight - buttonsHeight - topPadding - spacing

            VStack(spacing: spacing) {
                // Card stack
                ZStack {
                    ForEach(Array(engine.cards.prefix(3).enumerated().reversed()), id: \.element.id) { index, track in
                        let isTop = index == 0
                        SwipeCard(
                            track: track,
                            width: cardWidth,
                            height: cardHeight,
                            onSwipe: { liked in handleSwipe(track: track, liked: liked) },
                            onTapArtwork: { handleArtworkTap(track: track) },
                            onLongPress: { detailTrack = track }
                        )
                        .scaleEffect(isTop ? 1 : 1 - CGFloat(index) * 0.04)
                        .offset(y: isTop ? 0 : CGFloat(index) * 8)
                        .allowsHitTesting(isTop)
                    }
                }
                .padding(.top, topPadding)

                // Action buttons
                actionButtons
            }
            .frame(width: safeWidth, height: safeHeight)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 60) {
            // Dislike
            actionButton(
                icon: "xmark",
                color: .red,
                size: 72
            ) {
                if let track = engine.cards.first {
                    handleSwipe(track: track, liked: false)
                }
            }

            // Like
            actionButton(
                icon: "heart.fill",
                color: .green,
                size: 72
            ) {
                if let track = engine.cards.first {
                    handleSwipe(track: track, liked: true)
                }
            }
        }
    }

    private func actionButton(icon: String, color: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.33, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: color.opacity(0.3), radius: 10, y: 2)
                }
                .overlay {
                    Circle()
                        .strokeBorder(color.opacity(0.35), lineWidth: 2)
                }
        }
        .buttonStyle(ScaleButtonStyle())
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
        HapticManager.notification(liked ? .success : .warning)

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
            player.forcePlay(track: track)
        }
    }

    private func updateGradient(for track: iTunesTrack) async {
        let colors = await ColorExtractor.shared.extractColors(from: track.artworkURL(size: 100))
        withAnimation(.easeInOut(duration: 0.6)) {
            gradientColors = colors
        }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Swipe Card

struct SwipeCard: View {
    let track: iTunesTrack
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
            // Artwork — takes most of the card
            artworkView
                .padding(.top, 20)
                .padding(.horizontal, 20)

            Spacer(minLength: 12)

            // Track info
            trackInfo
                .padding(.horizontal, 20)

            // Progress bar
            if isCurrentTrack {
                progressBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer(minLength: 16)
        }
        .frame(width: width, height: height)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(swipeBorderGradient, lineWidth: 2.5)
        }
        .offset(x: offset.width, y: offset.height * 0.25)
        .rotationEffect(.degrees(Double(offset.width) / 25))
        // Swipe overlay indicators
        .overlay(alignment: .topLeading) {
            swipeLabel("NOPE", color: .red)
                .opacity(max(0, -swipeProgress - 0.2))
                .padding(24)
        }
        .overlay(alignment: .topTrailing) {
            swipeLabel("LIKE", color: .green)
                .opacity(max(0, swipeProgress - 0.2))
                .padding(24)
        }
        .gesture(swipeGesture)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkView: some View {
        // Artwork fills width minus padding, aspect ratio 1:1
        let artworkSize = width - 40

        ZStack {
            AsyncArtwork(url: track.artworkURL(size: 600), size: artworkSize, radius: 18)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .scaleEffect(isPressed ? 0.96 : 1)
                .animation(.spring(duration: 0.2), value: isPressed)

            // Play/Pause overlay on tap
            if isCurrentTrack && !isPlayingThis {
                Circle()
                    .fill(.black.opacity(0.35))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
            }
        }
        .onTapGesture { onTapArtwork() }
        .onLongPressGesture(minimumDuration: 0.5) {
            HapticManager.impact(.medium)
            onLongPress()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(spacing: 5) {
            Text(track.title)
                .font(.title3.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text(track.artistName)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            HStack(spacing: 8) {
                if let genre = track.genre {
                    Text(genre)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white.opacity(0.7))
                }
                if let year = track.releaseYear {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: 4)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * player.progress), height: 4)
                    .animation(.linear(duration: 0.25), value: player.progress)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Swipe Label Overlay

    private func swipeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.title.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color, lineWidth: 3)
            }
            .rotationEffect(.degrees(text == "NOPE" ? -15 : 15))
    }

    // MARK: - Swipe Border

    private var swipeBorderGradient: some ShapeStyle {
        if swipeProgress > 0.3 {
            return AnyShapeStyle(.green.opacity(Double(swipeProgress) * 0.6))
        }
        if swipeProgress < -0.3 {
            return AnyShapeStyle(.red.opacity(Double(-swipeProgress) * 0.6))
        }
        return AnyShapeStyle(.white.opacity(0.08))
    }

    // MARK: - Gesture

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
