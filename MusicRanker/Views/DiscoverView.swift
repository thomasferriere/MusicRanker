import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var trendingService: TrendingService

    @State private var gradientColors: [Color] = ColorExtractor.fallbackColors
    @State private var detailTrack: iTunesTrack?
    @State private var playlistTarget: iTunesTrack?

    @State private var discoverSections: [DiscoverSection] = []
    @State private var isLoadingSections = false
    @State private var scrollOffset: CGFloat = 0

    // Living gradient
    @State private var gradientPhase: CGFloat = 0
    @State private var gradientTimer: Timer?

    var body: some View {
        ZStack {
            // Living gradient background
            livingGradientBackground
                .ignoresSafeArea()

            if engine.isLoading && engine.cards.isEmpty {
                loadingState
            } else if engine.cards.isEmpty {
                emptyState
            } else {
                mainContent
            }
        }
        .task {
            await engine.loadInitialCards()
            if let first = engine.cards.first {
                player.forcePlay(track: first)
                await updateGradient(for: first)
            }
            async let trends: () = trendingService.loadTrending()
            async let sections: () = loadDiscoverSections()
            _ = await (trends, sections)
        }
        .onAppear { startGradientBreathing() }
        .onDisappear { stopGradientBreathing() }
        .sheet(item: $detailTrack) { track in
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

    // MARK: - Living Gradient Background

    private var livingGradientBackground: some View {
        let breathOffset = sin(gradientPhase) * 0.08
        let baseColors = gradientColors.isEmpty ? ColorExtractor.fallbackColors : gradientColors

        return ZStack {
            // Primary gradient layer
            LinearGradient(
                colors: baseColors + [Color.black],
                startPoint: UnitPoint(x: 0.2 + breathOffset, y: 0.0 + breathOffset * 0.5),
                endPoint: UnitPoint(x: 0.8 - breathOffset, y: 1.0 - breathOffset * 0.3)
            )

            // Secondary subtle layer for depth
            RadialGradient(
                colors: [
                    baseColors.first?.opacity(0.2 + breathOffset * 0.5) ?? .clear,
                    .clear
                ],
                center: UnitPoint(x: 0.3 + breathOffset * 2, y: 0.25),
                startRadius: 50,
                endRadius: 400
            )
            .blendMode(.screen)
        }
        .animation(.easeInOut(duration: 0.8), value: gradientColors.map(\.description))
        .drawingGroup() // GPU-accelerated
    }

    private func startGradientBreathing() {
        gradientTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                gradientPhase += 0.015
            }
        }
    }

    private func stopGradientBreathing() {
        gradientTimer?.invalidate()
        gradientTimer = nil
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Scroll offset tracker
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                // Immersive hero zone
                heroZone

                // Trending
                if !trendingService.trendingTracks.isEmpty {
                    trendingSection
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Personalized sections
                if !discoverSections.isEmpty {
                    personalizedSections
                        .padding(.top, 22)
                } else if isLoadingSections {
                    loadingSectionsPlaceholder
                        .padding(.top, 22)
                }

                Spacer(minLength: 100)
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }

    // MARK: - Immersive Hero Zone

    private var heroZone: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let cardWidth = screenW - 32
            let cardHeight = min(cardWidth * 1.35, 560)

            // Parallax: card scales down slightly as you scroll
            let scrollClamped = max(0, -scrollOffset)
            let heroScale = max(0.88, 1.0 - scrollClamped / 1200)
            let parallaxOffset = scrollClamped * 0.15

            ZStack {
                ForEach(Array(engine.cards.prefix(3).enumerated().reversed()), id: \.element.id) { index, track in
                    let isTop = index == 0
                    ImmersiveHeroCard(
                        track: track,
                        width: cardWidth,
                        height: cardHeight,
                        onSwipe: { liked in handleSwipe(track: track, liked: liked) },
                        onTapArtwork: { handleArtworkTap(track: track) },
                        onLongPress: { detailTrack = track },
                        onLike: {
                            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                                handleSwipe(track: track, liked: true)
                            }
                        },
                        onDislike: {
                            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                                handleSwipe(track: track, liked: false)
                            }
                        }
                    )
                    .scaleEffect(isTop ? 1.0 : 1.0 - CGFloat(index) * 0.035)
                    .offset(y: isTop ? 0 : CGFloat(index) * 10)
                    .opacity(isTop ? 1 : 0.65 - CGFloat(index) * 0.2)
                    .allowsHitTesting(isTop)
                }
            }
            .scaleEffect(heroScale)
            .offset(y: parallaxOffset)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 572)
    }

    // MARK: - Trending Section

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Tendances")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(countryFlag(trendingService.countryCode))
                            .font(.subheadline)
                    }
                    Text("Top charts en ce moment")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(trendingService.trendingTracks.prefix(15).enumerated()), id: \.element.id) { index, track in
                        TrendingCard(track: track, rank: index + 1) {
                            HapticManager.impact(.light)
                            if player.isCurrent(id: track.id) {
                                player.togglePause()
                            } else {
                                player.forcePlay(track: track)
                            }
                        }
                        .contextMenu { trackContextMenu(track: track) }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Personalized Sections

    private var personalizedSections: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(discoverSections) { section in
                discoverSectionView(section)
            }
        }
    }

    private func discoverSectionView(_ section: DiscoverSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(section.accentColor)
                    .frame(width: 24, height: 24)
                    .background(section.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    if let subtitle = section.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(section.tracks) { track in
                        DiscoverTrackCard(track: track) {
                            HapticManager.impact(.light)
                            if player.isCurrent(id: track.id) {
                                player.togglePause()
                            } else {
                                player.forcePlay(track: track)
                            }
                        }
                        .contextMenu { trackContextMenu(track: track) }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Loading Sections Placeholder

    private var loadingSectionsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.white.opacity(0.06))
                            .frame(width: 24, height: 24)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.06))
                            .frame(width: 120, height: 14)
                        Spacer()
                    }
                    .padding(.horizontal, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.white.opacity(0.06))
                                        .frame(width: 140, height: 140)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.05))
                                        .frame(width: 100, height: 10)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.03))
                                        .frame(width: 70, height: 8)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trackContextMenu(track: iTunesTrack) -> some View {
        Button {
            player.forcePlay(track: track)
        } label: {
            Label("Écouter", systemImage: "play.fill")
        }

        Button {
            HapticManager.notification(.success)
            engine.saveFeedback(track: track, liked: true)
        } label: {
            Label("J'aime", systemImage: engine.isTrackLiked(id: track.id) ? "heart.fill" : "heart")
        }

        Button {
            playlistTarget = track
        } label: {
            Label("Ajouter à une playlist", systemImage: "text.badge.plus")
        }

        Divider()

        Button {
            detailTrack = track
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
        withAnimation(.easeInOut(duration: 0.8)) {
            gradientColors = colors
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

    // MARK: - Load Discover Sections

    private func loadDiscoverSections() async {
        guard discoverSections.isEmpty else { return }
        isLoadingSections = true

        let profile = engine.buildTasteProfile()
        let service = iTunesService.shared
        let year = Calendar.current.component(.year, from: Date())
        var sections: [DiscoverSection] = []

        if let topGenre = profile.topGenres.first?.name {
            async let newTracks = service.search(term: "\(topGenre) \(year) new", limit: 20)
            let filtered = await newTracks.filter { $0.previewURL != nil }
            if filtered.count >= 3 {
                sections.append(DiscoverSection(
                    title: "Nouveautés pour toi",
                    subtitle: "Basé sur tes goûts en \(topGenre)",
                    icon: "sparkles",
                    accentColor: .cyan,
                    tracks: Array(filtered.prefix(10))
                ))
            }
        }

        if let topArtist = profile.topArtists.first {
            let tracks = await service.search(term: "\(topArtist.name) similar", limit: 20)
            let filtered = tracks.filter { $0.previewURL != nil && $0.artistName.lowercased() != topArtist.name.lowercased() }
            if filtered.count >= 3 {
                sections.append(DiscoverSection(
                    title: "Si tu aimes \(topArtist.name)",
                    subtitle: "Artistes similaires",
                    icon: "person.2.fill",
                    accentColor: .pink,
                    tracks: Array(filtered.prefix(10))
                ))
            }
        }

        let (moodLabel, moodTerm) = moodForEnergy(profile.averageEnergy)
        let moodTracks = await service.search(term: moodTerm, limit: 15)
        let moodFiltered = moodTracks.filter { $0.previewURL != nil }.shuffled()
        if moodFiltered.count >= 3 {
            sections.append(DiscoverSection(
                title: "Ambiance \(moodLabel)",
                subtitle: "Des sons pour ton mood",
                icon: "waveform",
                accentColor: .purple,
                tracks: Array(moodFiltered.prefix(10))
            ))
        }

        async let pepite1 = service.search(term: "indie \(year) new", limit: 12)
        async let pepite2 = service.search(term: "underground \(year)", limit: 12)
        let allPepites = await (pepite1 + pepite2).filter { $0.previewURL != nil }.shuffled()
        if allPepites.count >= 3 {
            sections.append(DiscoverSection(
                title: "Pépites récentes",
                subtitle: "Hors des radars",
                icon: "diamond.fill",
                accentColor: .yellow,
                tracks: Array(allPepites.prefix(10))
            ))
        }

        if profile.topGenres.count >= 2 {
            let secondGenre = profile.topGenres[1].name
            let tracks = await service.search(term: "\(secondGenre) \(year)", limit: 15)
            let filtered = tracks.filter { $0.previewURL != nil }
            if filtered.count >= 3 {
                sections.append(DiscoverSection(
                    title: "À écouter ensuite",
                    subtitle: "Explore le \(secondGenre)",
                    icon: "arrow.right.circle.fill",
                    accentColor: .orange,
                    tracks: Array(filtered.prefix(10))
                ))
            }
        }

        let mixGenres = ["afrobeats", "k-pop", "jazz", "reggaeton", "funk", "soul", "techno", "bossa nova"]
        let unexplored = mixGenres.filter { genre in
            !profile.topGenres.contains { $0.name.lowercased() == genre }
        }
        if let discoveryGenre = unexplored.randomElement() {
            let tracks = await service.search(term: "\(discoveryGenre) \(year)", limit: 15)
            let filtered = tracks.filter { $0.previewURL != nil }
            if filtered.count >= 3 {
                sections.append(DiscoverSection(
                    title: "Découverte : \(discoveryGenre.capitalized)",
                    subtitle: "Sors de ta zone de confort",
                    icon: "globe",
                    accentColor: .green,
                    tracks: Array(filtered.prefix(10))
                ))
            }
        }

        if profile.topArtists.count >= 2 {
            let artist = profile.topArtists[min(1, profile.topArtists.count - 1)]
            if let artistId = artist.ids.first {
                let tracks = await service.lookupArtist(id: artistId, limit: 15)
                let filtered = tracks.filter { $0.previewURL != nil }
                if filtered.count >= 3 {
                    sections.append(DiscoverSection(
                        title: "Redécouvrir \(artist.name)",
                        subtitle: "Des anciens coups de coeur",
                        icon: "arrow.counterclockwise",
                        accentColor: .teal,
                        tracks: Array(filtered.prefix(10))
                    ))
                }
            }
        }

        discoverSections = sections
        isLoadingSections = false
    }

    private func moodForEnergy(_ energy: Double) -> (String, String) {
        switch energy {
        case 0..<0.35: ("Chill", "chill relax calm ambient lo-fi")
        case 0.35..<0.55: ("Easy", "feel good vibes smooth soul")
        case 0.55..<0.75: ("Upbeat", "happy upbeat fun summer party")
        default: ("Intense", "workout hype energy bass hard")
        }
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Discover Section Model

struct DiscoverSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let accentColor: Color
    let tracks: [iTunesTrack]

    init(title: String, subtitle: String?, icon: String, accentColor: Color, tracks: [iTunesTrack]) {
        self.id = title
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accentColor = accentColor
        self.tracks = tracks
    }
}

// MARK: - Immersive Hero Card

struct ImmersiveHeroCard: View {
    let track: iTunesTrack
    let width: CGFloat
    let height: CGFloat
    let onSwipe: (Bool) -> Void
    let onTapArtwork: () -> Void
    let onLongPress: () -> Void
    let onLike: () -> Void
    let onDislike: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @State private var offset: CGSize = .zero
    @State private var isPressed = false

    // Like/dislike micro-interaction states
    @State private var likeGlow: CGFloat = 0
    @State private var dislikeShake: CGFloat = 0

    private var swipeProgress: CGFloat { offset.width / 150 }
    private var isPlayingThis: Bool { player.isCurrentlyPlaying(id: track.id) }
    private var isCurrentTrack: Bool { player.isCurrent(id: track.id) }

    // Dynamic shadow reacts to swipe
    private var dynamicShadowColor: Color {
        if swipeProgress > 0.2 { return .green.opacity(0.3) }
        if swipeProgress < -0.2 { return .red.opacity(0.3) }
        return .black.opacity(0.5)
    }

    private var dynamicShadowRadius: CGFloat {
        let base: CGFloat = 30
        return base + abs(swipeProgress) * 15
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            artworkLayer
            bottomOverlay
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        // Dynamic shadow reacts to swipe direction
        .shadow(color: dynamicShadowColor, radius: dynamicShadowRadius, y: 12)
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        // Swipe border glow
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(swipeBorderColor, lineWidth: 2.5)
        }
        // Like glow overlay
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .fill(.green.opacity(likeGlow * 0.15))
                .allowsHitTesting(false)
        }
        // LIKE / NOPE stamps
        .overlay(alignment: .topLeading) {
            swipeStamp("NOPE", color: .red)
                .opacity(max(0, -swipeProgress - 0.12))
                .padding(24)
        }
        .overlay(alignment: .topTrailing) {
            swipeStamp("LIKE", color: .green)
                .opacity(max(0, swipeProgress - 0.12))
                .padding(24)
        }
        // Swipe transform — rotation proportional to distance, scale reduces slightly
        .offset(x: offset.width, y: offset.height * 0.12)
        .rotationEffect(.degrees(Double(offset.width) / 28))
        .scaleEffect(isPressed ? 0.975 : 1.0 - abs(swipeProgress) * 0.02)
        // Dislike shake
        .offset(x: dislikeShake)
        .animation(.spring(duration: 0.2), value: isPressed)
        .gesture(swipeGesture)
    }

    // MARK: - Artwork with Parallax

    private var artworkLayer: some View {
        Group {
            if let url = track.artworkURL(size: 900) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            // Parallax: artwork moves slower than container during swipe
                            .frame(width: width + 30, height: height + 30)
                            .offset(x: -offset.width * 0.08, y: -15)
                            .clipped()
                    case .failure:
                        artworkPlaceholder
                    default:
                        artworkPlaceholder
                            .overlay {
                                ProgressView()
                                    .tint(.white.opacity(0.4))
                                    .scaleEffect(1.2)
                            }
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .onTapGesture { onTapArtwork() }
        .onLongPressGesture(minimumDuration: 0.4) {
            HapticManager.impact(.medium)
            onLongPress()
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(.gray.opacity(0.12))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.15))
            }
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                // Track info
                VStack(spacing: 5) {
                    Text(track.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)

                    Text(track.artistName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)

                    HStack(spacing: 8) {
                        if let genre = track.genre {
                            Text(genre)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3.5)
                                .background(.white.opacity(0.15), in: Capsule())
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        if let year = track.releaseYear {
                            Text(year)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }

                // Animated progress zone
                if isCurrentTrack {
                    HStack(spacing: 8) {
                        // Live waveform bars
                        LiveWaveformView(isAnimating: isPlayingThis)
                            .frame(width: 20, height: 14)

                        // Progress bar with glow
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.12))
                                    .frame(height: 3.5)
                                Capsule()
                                    .fill(.white.opacity(0.75))
                                    .frame(width: max(0, geo.size.width * player.progress), height: 3.5)
                                    .shadow(color: .white.opacity(0.3), radius: 4, y: 0)
                                    .animation(.linear(duration: 0.3), value: player.progress)
                            }
                        }
                        .frame(height: 3.5)

                        if let dur = track.formattedDuration {
                            Text(dur)
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Integrated action buttons
                HStack(spacing: 0) {
                    Button {
                        triggerDislike()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.08), in: Circle())
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1)
                            }
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Spacer()

                    Button {
                        triggerLike()
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.pink.opacity(0.8 + likeGlow * 0.2))
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.08), in: Circle())
                            .overlay {
                                Circle().strokeBorder(.pink.opacity(0.15 + likeGlow * 0.3), lineWidth: 1)
                            }
                            .scaleEffect(1.0 + likeGlow * 0.15)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 80)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.15), location: 0.12),
                        .init(color: .black.opacity(0.5), location: 0.4),
                        .init(color: .black.opacity(0.78), location: 0.72),
                        .init(color: .black.opacity(0.92), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Micro Interactions

    private func triggerLike() {
        HapticManager.impact(.light)
        // Pulse glow
        withAnimation(.easeOut(duration: 0.15)) {
            likeGlow = 1.0
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.15)) {
            likeGlow = 0
        }
        // Delay the actual swipe slightly so the glow is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            onLike()
        }
    }

    private func triggerDislike() {
        HapticManager.impact(.rigid)
        // Lateral shake
        withAnimation(.spring(duration: 0.08)) { dislikeShake = -6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.spring(duration: 0.08)) { dislikeShake = 6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(duration: 0.08)) { dislikeShake = -3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(duration: 0.1)) { dislikeShake = 0 }
            onDislike()
        }
    }

    // MARK: - Swipe Gesture (physics-based)

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                // Card follows finger with slight damping
                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.85)) {
                    offset = value.translation
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 90
                let velocity = value.predictedEndTranslation.width
                let speed = abs(velocity)

                if value.translation.width > threshold || velocity > 300 {
                    // Like — fly off with velocity-based duration
                    let duration = max(0.15, min(0.35, 200 / speed))
                    withAnimation(.easeOut(duration: duration)) {
                        offset = CGSize(width: 600, height: velocity * 0.05)
                    }
                    HapticManager.notification(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.6) {
                        onSwipe(true)
                    }
                } else if value.translation.width < -threshold || velocity < -300 {
                    // Dislike — fly off faster
                    let duration = max(0.12, min(0.3, 200 / speed))
                    withAnimation(.easeOut(duration: duration)) {
                        offset = CGSize(width: -600, height: velocity * 0.05)
                    }
                    HapticManager.notification(.warning)
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.6) {
                        onSwipe(false)
                    }
                } else {
                    // Spring back with natural bounce
                    withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                        offset = .zero
                    }
                    HapticManager.selection()
                }
            }
    }

    // MARK: - Helpers

    private func swipeStamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.title2.bold())
            .tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(color, lineWidth: 3)
            }
            .rotationEffect(.degrees(text == "NOPE" ? -18 : 18))
            .shadow(color: color.opacity(0.35), radius: 10, y: 2)
    }

    private var swipeBorderColor: some ShapeStyle {
        if swipeProgress > 0.2 {
            AnyShapeStyle(.green.opacity(Double(swipeProgress) * 0.9))
        } else if swipeProgress < -0.2 {
            AnyShapeStyle(.red.opacity(Double(-swipeProgress) * 0.9))
        } else {
            AnyShapeStyle(.white.opacity(0.04))
        }
    }
}

// MARK: - Live Waveform View (animated bars)

struct LiveWaveformView: View {
    let isAnimating: Bool

    @State private var heights: [CGFloat] = [0.3, 0.6, 0.4, 0.8, 0.5]
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.65))
                    .frame(width: 2, height: heights[i] * 14)
                    .frame(height: 14, alignment: .bottom)
            }
        }
        .onAppear { if isAnimating { startAnimation() } }
        .onChange(of: isAnimating) { _, active in
            if active { startAnimation() } else { stopAnimation() }
        }
        .onDisappear { stopAnimation() }
    }

    private func startAnimation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.15)) {
                    heights = (0..<5).map { _ in CGFloat.random(in: 0.2...1.0) }
                }
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
        withAnimation(.easeOut(duration: 0.3)) {
            heights = [0.2, 0.2, 0.2, 0.2, 0.2]
        }
    }
}

// MARK: - Trending Card

struct TrendingCard: View {
    let track: iTunesTrack
    let rank: Int
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                AsyncArtwork(url: track.artworkURL(size: 400), size: 150, radius: 14)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                if isPlaying {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            LiveWaveformView(isAnimating: true)
                                .frame(width: 20, height: 14)
                                .padding(6)
                                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                                .padding(6)
                        }
                    }
                }

                VStack {
                    HStack {
                        Text("\(rank)")
                            .font(.system(size: rank <= 9 ? 22 : 17, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(minWidth: 32, minHeight: 32)
                            .background {
                                Circle()
                                    .fill(
                                        rank == 1 ? AnyShapeStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)) :
                                        rank == 2 ? AnyShapeStyle(LinearGradient(colors: [.gray, .white.opacity(0.6)], startPoint: .top, endPoint: .bottom)) :
                                        rank == 3 ? AnyShapeStyle(LinearGradient(colors: [.brown, .orange.opacity(0.5)], startPoint: .top, endPoint: .bottom)) :
                                        AnyShapeStyle(.black.opacity(0.6))
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            }
                            .padding(8)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(width: 150, height: 150)
            .onTapGesture { onTap() }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(track.artistName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

// MARK: - Discover Track Card

struct DiscoverTrackCard: View {
    let track: iTunesTrack
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                AsyncArtwork(url: track.artworkURL(size: 300), size: 140, radius: 12)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                if isPlaying {
                    LiveWaveformView(isAnimating: true)
                        .frame(width: 18, height: 12)
                        .padding(4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                        .padding(6)
                }
            }
            .onTapGesture { onTap() }

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(track.artistName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
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
                        img.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    default:
                        placeholder.overlay { ProgressView().tint(.secondary) }
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
