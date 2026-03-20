import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var trendingService: TrendingService

    @State private var gradientColors: [Color] = ColorExtractor.fallbackColors
    @State private var detailTrack: iTunesTrack?
    @State private var playlistTarget: iTunesTrack?

    // Rich sections
    @State private var discoverSections: [DiscoverSection] = []
    @State private var isLoadingSections = false
    @State private var cardZoneHeight: CGFloat = 472

    var body: some View {
        ZStack {
            // Dynamic gradient background
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
            // Load trending + sections in parallel
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

    // MARK: - Main Content (Scrollable with card + sections)

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Compact swipe card zone
                swipeCardZone
                    .padding(.top, 4)

                // Rich sections below (visible without scrolling much)
                VStack(alignment: .leading, spacing: 0) {
                    // Trending section (real data)
                    if !trendingService.trendingTracks.isEmpty {
                        trendingInlineSection
                            .padding(.top, 24)
                    }

                    // Personalized sections
                    if !discoverSections.isEmpty {
                        richSections
                            .padding(.top, 24)
                    } else if isLoadingSections {
                        loadingSectionsPlaceholder
                            .padding(.top, 28)
                    }
                }

                Spacer(minLength: 120)
            }
        }
    }

    // MARK: - Swipe Card Zone (more compact)

    private var swipeCardZone: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width - 56
            let cardHeight: CGFloat = min(geo.size.width * 0.95, 400)

            VStack(spacing: 12) {
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
                        .offset(y: isTop ? 0 : CGFloat(index) * 6)
                        .allowsHitTesting(isTop)
                    }
                }

                // Compact action buttons
                HStack(spacing: 44) {
                    actionButton(icon: "xmark", color: .red, size: 48) {
                        if let track = engine.cards.first {
                            handleSwipe(track: track, liked: false)
                        }
                    }

                    actionButton(icon: "heart.fill", color: .green, size: 48) {
                        if let track = engine.cards.first {
                            handleSwipe(track: track, liked: true)
                        }
                    }
                }
            }
            .onAppear {
                cardZoneHeight = min(geo.size.width * 0.95 + 72, 472)
            }
        }
        .frame(height: cardZoneHeight)
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
                        .shadow(color: color.opacity(0.25), radius: 8, y: 2)
                }
                .overlay {
                    Circle()
                        .strokeBorder(color.opacity(0.3), lineWidth: 1.5)
                }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Trending Inline Section (real data from TrendingService)

    private var trendingInlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                Text("Tendances")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text(countryFlag(trendingService.countryCode))
                    .font(.caption)

                Spacer()

                Text(trendingService.sourceName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 20)

            // Horizontal trending cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(trendingService.trendingTracks.prefix(12).enumerated()), id: \.element.id) { index, track in
                        TrendingCompactCard(track: track, rank: index + 1) {
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

    // MARK: - Rich Sections

    private var richSections: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(discoverSections) { section in
                discoverSectionView(section)
            }
        }
    }

    private func discoverSectionView(_ section: DiscoverSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(section.accentColor)
                    .frame(width: 22, height: 22)
                    .background(section.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

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
            .padding(.horizontal, 20)

            // Horizontal cards
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
                        .contextMenu {
                            trackContextMenu(track: track)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Loading Sections Placeholder

    private var loadingSectionsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.06))
                            .frame(width: 22, height: 22)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.06))
                            .frame(width: 120, height: 14)
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.white.opacity(0.06))
                                        .frame(width: 130, height: 130)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.06))
                                        .frame(width: 90, height: 10)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.white.opacity(0.04))
                                        .frame(width: 60, height: 8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
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

        // 1. Nouveautés pour toi
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

        // 2. Artistes similaires
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

        // 3. Par ambiance
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

        // 4. Pépites récentes
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

        // 5. À écouter ensuite (based on recent likes)
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

        // 6. Mix varié
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

        // 7. Redécouvrir
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
        self.id = title // Stable ID based on title
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accentColor = accentColor
        self.tracks = tracks
    }
}

// MARK: - Trending Compact Card (with rank, for Discover)

struct TrendingCompactCard: View {
    let track: iTunesTrack
    let rank: Int
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Rank number
                Text("\(rank)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(rank <= 3 ? .orange : .white.opacity(0.35))
                    .frame(width: 20)

                // Artwork
                ZStack(alignment: .bottomTrailing) {
                    AsyncArtwork(url: track.artworkURL(size: 200), size: 48, radius: 8)

                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                            .padding(3)
                            .background(.black.opacity(0.5), in: Circle())
                            .offset(x: 2, y: 2)
                    }
                }

                // Info
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
                .frame(width: 100, alignment: .leading)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Discover Track Card (lightweight, premium)

struct DiscoverTrackCard: View {
    let track: iTunesTrack
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager

    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                AsyncArtwork(url: track.artworkURL(size: 300), size: 130, radius: 10)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                        .padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(5)
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
            .frame(width: 130, alignment: .leading)
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
            artworkView
                .padding(.top, 12)
                .padding(.horizontal, 12)

            Spacer(minLength: 6)

            trackInfo
                .padding(.horizontal, 14)

            if isCurrentTrack {
                progressBar
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            Spacer(minLength: 10)
        }
        .frame(width: width, height: height)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(swipeBorderGradient, lineWidth: 2)
        }
        .offset(x: offset.width, y: offset.height * 0.25)
        .rotationEffect(.degrees(Double(offset.width) / 25))
        .overlay(alignment: .topLeading) {
            swipeLabel("NOPE", color: .red)
                .opacity(max(0, -swipeProgress - 0.2))
                .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            swipeLabel("LIKE", color: .green)
                .opacity(max(0, swipeProgress - 0.2))
                .padding(16)
        }
        .gesture(swipeGesture)
    }

    @ViewBuilder
    private var artworkView: some View {
        let artworkSize = width - 24

        ZStack {
            AsyncArtwork(url: track.artworkURL(size: 600), size: artworkSize, radius: 14)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .scaleEffect(isPressed ? 0.96 : 1)
                .animation(.spring(duration: 0.2), value: isPressed)

            if isCurrentTrack && !isPlayingThis {
                Circle()
                    .fill(.black.opacity(0.35))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.semibold))
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

    private var trackInfo: some View {
        VStack(spacing: 3) {
            Text(track.title)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text(track.artistName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)

            HStack(spacing: 6) {
                if let genre = track.genre {
                    Text(genre)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1), in: Capsule())
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let year = track.releaseYear {
                    Text(year)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.top, 1)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * player.progress), height: 3)
                    .animation(.linear(duration: 0.25), value: player.progress)
            }
        }
        .frame(height: 3)
    }

    private func swipeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.headline.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color, lineWidth: 2.5)
            }
            .rotationEffect(.degrees(text == "NOPE" ? -15 : 15))
    }

    private var swipeBorderGradient: some ShapeStyle {
        if swipeProgress > 0.3 {
            AnyShapeStyle(.green.opacity(Double(swipeProgress) * 0.6))
        } else if swipeProgress < -0.3 {
            AnyShapeStyle(.red.opacity(Double(-swipeProgress) * 0.6))
        } else {
            AnyShapeStyle(.white.opacity(0.06))
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in offset = value.translation }
            .onEnded { value in
                let threshold: CGFloat = 120
                if value.translation.width > threshold {
                    animateOff(direction: 1); onSwipe(true)
                } else if value.translation.width < -threshold {
                    animateOff(direction: -1); onSwipe(false)
                } else {
                    withAnimation(.spring(duration: 0.3)) { offset = .zero }
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
