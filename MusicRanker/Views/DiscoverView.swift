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
    @State private var heroHeight: CGFloat = 540

    var body: some View {
        ZStack {
            // Dynamic gradient background — extends behind everything
            LinearGradient(
                colors: gradientColors + [Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: gradientColors.map(\.description))

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

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Immersive hero zone (card + integrated actions)
                heroZone

                // Trending — real data, tight transition
                if !trendingService.trendingTracks.isEmpty {
                    trendingSection
                        .padding(.top, 20)
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
    }

    // MARK: - Immersive Hero Zone

    private var heroZone: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width - 32 // Near full-width (16pt each side)
            let cardHeight = min(cardWidth * 1.35, geo.size.height * 0.72)

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
                        onLike: { handleSwipe(track: track, liked: true) },
                        onDislike: { handleSwipe(track: track, liked: false) }
                    )
                    .scaleEffect(isTop ? 1.0 : 1.0 - CGFloat(index) * 0.035)
                    .offset(y: isTop ? 0 : CGFloat(index) * 10)
                    .opacity(isTop ? 1 : 0.7 - CGFloat(index) * 0.2)
                    .allowsHitTesting(isTop)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                heroHeight = cardHeight + 12
            }
        }
        .frame(height: heroHeight)
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
        withAnimation(.easeInOut(duration: 0.6)) {
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

// MARK: - Discover Section Model (stable ID)

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

// MARK: - Immersive Hero Card (artwork-dominant, actions integrated)

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

    private var swipeProgress: CGFloat { offset.width / 150 }
    private var isPlayingThis: Bool { player.isCurrentlyPlaying(id: track.id) }
    private var isCurrentTrack: Bool { player.isCurrent(id: track.id) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed artwork
            artworkLayer

            // Bottom zone: gradient + info + actions
            bottomOverlay
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.55), radius: 35, y: 14)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        // Swipe border glow
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(swipeBorderColor, lineWidth: 2.5)
        }
        // LIKE / NOPE labels
        .overlay(alignment: .topLeading) {
            swipeStamp("NOPE", color: .red)
                .opacity(max(0, -swipeProgress - 0.15))
                .padding(24)
        }
        .overlay(alignment: .topTrailing) {
            swipeStamp("LIKE", color: .green)
                .opacity(max(0, swipeProgress - 0.15))
                .padding(24)
        }
        // Transform
        .offset(x: offset.width, y: offset.height * 0.15)
        .rotationEffect(.degrees(Double(offset.width) / 30))
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .animation(.spring(duration: 0.2), value: isPressed)
        .gesture(swipeGesture)
    }

    // MARK: - Artwork

    private var artworkLayer: some View {
        Group {
            if let url = track.artworkURL(size: 900) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
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

    // MARK: - Bottom Overlay (info + progress + actions — all integrated)

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                // Track info — centered, breathing
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

                // Progress bar + waveform indicator
                if isCurrentTrack {
                    HStack(spacing: 10) {
                        // Subtle waveform (no text)
                        Image(systemName: isPlayingThis ? "waveform" : "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .symbolEffect(.variableColor.iterative, isActive: isPlayingThis)
                            .frame(width: 16)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.15))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(.white.opacity(0.65))
                                    .frame(width: max(0, geo.size.width * player.progress), height: 3)
                                    .animation(.linear(duration: 0.25), value: player.progress)
                            }
                        }
                        .frame(height: 3)

                        // Duration
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
                    // Dislike
                    Button {
                        onDislike()
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

                    // Like
                    Button {
                        onLike()
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.08), in: Circle())
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1)
                            }
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
                        .init(color: .black.opacity(0.2), location: 0.15),
                        .init(color: .black.opacity(0.55), location: 0.45),
                        .init(color: .black.opacity(0.8), location: 0.75),
                        .init(color: .black.opacity(0.92), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in offset = value.translation }
            .onEnded { value in
                let threshold: CGFloat = 100
                let velocity = value.predictedEndTranslation.width
                if value.translation.width > threshold || velocity > 350 {
                    animateOff(direction: 1); onSwipe(true)
                } else if value.translation.width < -threshold || velocity < -350 {
                    animateOff(direction: -1); onSwipe(false)
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.12)) { offset = .zero }
                }
            }
    }

    private func animateOff(direction: CGFloat) {
        withAnimation(.easeOut(duration: 0.25)) {
            offset = CGSize(width: direction * 500, height: direction * 20)
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
        if swipeProgress > 0.25 {
            AnyShapeStyle(.green.opacity(Double(swipeProgress) * 0.8))
        } else if swipeProgress < -0.25 {
            AnyShapeStyle(.red.opacity(Double(-swipeProgress) * 0.8))
        } else {
            AnyShapeStyle(.white.opacity(0.05))
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
                            Image(systemName: "waveform")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                                .padding(5)
                                .background(.black.opacity(0.55), in: Circle())
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
                    Image(systemName: "waveform")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                        .padding(4)
                        .background(.black.opacity(0.5), in: Circle())
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
