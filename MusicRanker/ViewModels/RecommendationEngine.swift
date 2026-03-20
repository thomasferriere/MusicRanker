import Foundation
import CoreData

/// V2 Recommendation Engine with hybrid scoring system
@MainActor
final class RecommendationEngine: ObservableObject {

    // MARK: - Published State

    @Published var cards: [iTunesTrack] = []
    @Published var isLoading = false
    @Published var forYouSections: [ForYouSection] = []
    @Published var isLoadingForYou = false

    // MARK: - Dependencies

    private let context: NSManagedObjectContext
    private let service: MusicSearchService
    private var seenIDs: Set<String> = []
    private var recentCardArtists: [String] = [] // last N artists shown
    private var recentCardGenres: [String] = []  // last N genres shown
    private var fetchTask: Task<Void, Never>?

    // MARK: - Scoring Weights

    private struct Weights {
        static let userTaste: Double = 0.30
        static let recency: Double = 0.20
        static let diversity: Double = 0.20
        static let exploration: Double = 0.10
        static let artistRepetition: Double = 0.25
        static let genreRedundancy: Double = 0.10
    }

    // MARK: - Genre Energy Map (approximate "vibe" clustering)

    private static let genreEnergy: [String: Double] = [
        "Hip-Hop/Rap": 0.80, "Pop": 0.65, "Dance": 0.90,
        "Electronic": 0.85, "Rock": 0.75, "Alternative": 0.60,
        "R&B/Soul": 0.50, "Jazz": 0.30, "Classical": 0.20,
        "Country": 0.45, "Reggae": 0.40, "Latin": 0.70,
        "Metal": 0.95, "Blues": 0.35, "Funk": 0.70,
        "Soul": 0.45, "Worldwide": 0.55, "Singer/Songwriter": 0.35,
        "Soundtrack": 0.40, "Anime": 0.60, "J-Pop": 0.65,
        "K-Pop": 0.75, "French Pop": 0.55, "Musique": 0.50,
    ]

    // MARK: - Related Genres (for similarity scoring)

    private static let relatedGenres: [String: Set<String>] = [
        "Hip-Hop/Rap": ["R&B/Soul", "Pop", "Dance"],
        "Pop": ["Dance", "Electronic", "R&B/Soul", "French Pop"],
        "Rock": ["Alternative", "Metal", "Blues"],
        "Electronic": ["Dance", "Pop"],
        "R&B/Soul": ["Hip-Hop/Rap", "Pop", "Soul", "Funk"],
        "Jazz": ["Blues", "Soul", "Classical"],
        "Classical": ["Soundtrack", "Jazz"],
        "Latin": ["Reggae", "Pop", "Dance"],
        "Metal": ["Rock", "Alternative"],
        "Country": ["Rock", "Singer/Songwriter", "Blues"],
        "K-Pop": ["Pop", "Dance", "J-Pop"],
    ]

    // MARK: - Init

    init(context: NSManagedObjectContext, service: MusicSearchService = iTunesService.shared) {
        self.context = context
        self.service = service
        loadSeenIDs()
    }

    // MARK: - Taste Profile

    struct TasteProfile {
        let topArtists: [(name: String, count: Int, ids: [Int])]
        let topGenres: [(name: String, count: Int)]
        let genreWeights: [String: Double]  // normalized 0...1
        let artistWeights: [String: Double] // normalized 0...1
        let averageEnergy: Double
        let likedCount: Int
        let recentArtists: [String]     // last 10 liked artists
        let dislikedGenres: [String: Int] // genres from disliked songs
        let dislikedArtists: Set<String>  // frequently disliked artists
    }

    func buildTasteProfile() -> TasteProfile {
        let request = NSFetchRequest<SwipedSongEntity>(entityName: "SwipedSongEntity")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SwipedSongEntity.swipedAt, ascending: false)]

        guard let all = try? context.fetch(request) else {
            return TasteProfile(
                topArtists: [], topGenres: [], genreWeights: [:],
                artistWeights: [:], averageEnergy: 0.5, likedCount: 0,
                recentArtists: [], dislikedGenres: [:], dislikedArtists: []
            )
        }

        let liked = all.filter(\.isLiked)
        let disliked = all.filter { !$0.isLiked }

        // Artist analysis (liked)
        var artistCounts: [String: (count: Int, ids: Set<Int>)] = [:]
        for song in liked {
            guard let artist = song.artistName else { continue }
            var entry = artistCounts[artist] ?? (0, [])
            entry.count += 1
            if song.artistId > 0 { entry.ids.insert(Int(song.artistId)) }
            artistCounts[artist] = entry
        }
        let sortedArtists = artistCounts.sorted { $0.value.count > $1.value.count }
        let topArtists = sortedArtists.prefix(8).map {
            (name: $0.key, count: $0.value.count, ids: Array($0.value.ids))
        }

        // Genre analysis (liked)
        var genreCounts: [String: Int] = [:]
        var totalEnergy: Double = 0
        var energyCount = 0
        for song in liked {
            if let genre = song.genre, !genre.isEmpty {
                genreCounts[genre, default: 0] += 1
                if let energy = Self.genreEnergy[genre] {
                    totalEnergy += energy
                    energyCount += 1
                }
            }
        }
        let sortedGenres = genreCounts.sorted { $0.value > $1.value }
        let topGenres = sortedGenres.prefix(6).map { (name: $0.key, count: $0.value) }

        // Normalize weights
        let maxArtist = Double(sortedArtists.first?.value.count ?? 1)
        let artistWeights = Dictionary(uniqueKeysWithValues: sortedArtists.map {
            ($0.key, Double($0.value.count) / maxArtist)
        })
        let maxGenre = Double(sortedGenres.first?.value ?? 1)
        let genreWeights = Dictionary(uniqueKeysWithValues: sortedGenres.map {
            ($0.key, Double($0.value) / maxGenre)
        })

        // Average energy
        let avgEnergy = energyCount > 0 ? totalEnergy / Double(energyCount) : 0.5

        // Recent artists (last 10 liked)
        let recentArtists = liked.prefix(10).compactMap(\.artistName)

        // Disliked analysis
        var dislikedGenreCounts: [String: Int] = [:]
        var dislikedArtistCounts: [String: Int] = [:]
        for song in disliked {
            if let genre = song.genre { dislikedGenreCounts[genre, default: 0] += 1 }
            if let artist = song.artistName { dislikedArtistCounts[artist, default: 0] += 1 }
        }
        // Artists disliked 3+ times
        let dislikedArtists = Set(dislikedArtistCounts.filter { $0.value >= 3 }.keys)

        return TasteProfile(
            topArtists: Array(topArtists),
            topGenres: Array(topGenres),
            genreWeights: genreWeights,
            artistWeights: artistWeights,
            averageEnergy: avgEnergy,
            likedCount: liked.count,
            recentArtists: Array(recentArtists),
            dislikedGenres: dislikedGenreCounts,
            dislikedArtists: dislikedArtists
        )
    }

    // MARK: - Scoring System

    private struct ScoredTrack {
        let track: iTunesTrack
        let score: Double
    }

    private func scoreTrack(_ track: iTunesTrack, profile: TasteProfile) -> Double {
        var score: Double = 0

        // 1. User Taste Score (genre + artist match)
        var tasteScore: Double = 0
        if let genre = track.genre {
            // Direct genre match
            if let weight = profile.genreWeights[genre] {
                tasteScore += weight * 0.6
            }
            // Related genre match
            for (likedGenre, _) in profile.topGenres {
                if let related = Self.relatedGenres[likedGenre], related.contains(genre) {
                    tasteScore += 0.3
                    break
                }
            }
            // Energy compatibility
            let trackEnergy = Self.genreEnergy[genre] ?? 0.5
            let energyDiff = abs(trackEnergy - profile.averageEnergy)
            tasteScore += max(0, 1.0 - energyDiff * 2) * 0.3
        }
        // Artist match bonus
        if let artistWeight = profile.artistWeights[track.artistName] {
            tasteScore += artistWeight * 0.4
        }
        // Penalize disliked artists
        if profile.dislikedArtists.contains(track.artistName) {
            tasteScore -= 0.8
        }
        score += Weights.userTaste * min(tasteScore, 1.5)

        // 2. Recency Score
        var recencyScore: Double = 0.3 // default for unknown dates
        if let ageDays = track.ageDays {
            switch ageDays {
            case ..<90: recencyScore = 1.0
            case ..<365: recencyScore = 0.7
            case ..<1095: recencyScore = 0.4
            default: recencyScore = 0.15
            }
        }
        score += Weights.recency * recencyScore

        // 3. Diversity Boost
        var diversityScore: Double = 0
        if let genre = track.genre {
            // Bonus if this genre hasn't been shown recently
            if !recentCardGenres.suffix(5).contains(genre) {
                diversityScore += 0.6
            }
            // Bonus for genres user hasn't explored much
            if profile.genreWeights[genre] == nil {
                diversityScore += 0.4
            }
        }
        // Artist diversity
        if !recentCardArtists.suffix(3).contains(track.artistName) {
            diversityScore += 0.3
        }
        score += Weights.diversity * min(diversityScore, 1.0)

        // 4. Exploration Bonus (controlled randomness)
        let explorationBonus = Double.random(in: 0...0.15)
        score += Weights.exploration * explorationBonus

        // 5. Artist Repetition Penalty
        var repetitionPenalty: Double = 0
        let recentArtists3 = recentCardArtists.suffix(3)
        let recentArtists8 = recentCardArtists.suffix(8)
        if recentArtists3.contains(track.artistName) {
            repetitionPenalty = 1.0
        } else if recentArtists8.contains(track.artistName) {
            repetitionPenalty = 0.5
        }
        score -= Weights.artistRepetition * repetitionPenalty

        // 6. Genre Redundancy Penalty
        let recentGenres3 = recentCardGenres.suffix(3)
        if let genre = track.genre,
           recentGenres3.filter({ $0 == genre }).count >= 2 {
            score -= Weights.genreRedundancy * 0.8
        }

        return score
    }

    /// Sort and select the best tracks from a candidate pool
    private func rankTracks(_ candidates: [iTunesTrack], profile: TasteProfile, count: Int) -> [iTunesTrack] {
        let scored = candidates.map { ScoredTrack(track: $0, score: scoreTrack($0, profile: profile)) }
        let sorted = scored.sorted { $0.score > $1.score }
        return Array(sorted.prefix(count).map(\.track))
    }

    // MARK: - Swipe Cards

    func loadInitialCards() async {
        guard cards.isEmpty else { return }
        isLoading = true
        await fetchMoreCards()
        isLoading = false
    }

    func cardSwiped(_ track: iTunesTrack, liked: Bool) {
        seenIDs.insert(String(track.id))
        recentCardArtists.append(track.artistName)
        if let genre = track.genre { recentCardGenres.append(genre) }

        // Keep recent lists bounded
        if recentCardArtists.count > 20 { recentCardArtists.removeFirst(10) }
        if recentCardGenres.count > 20 { recentCardGenres.removeFirst(10) }

        saveSwiped(track, liked: liked)

        if cards.count < 3 {
            fetchTask?.cancel()
            fetchTask = Task { await fetchMoreCards() }
        }
    }

    private func fetchMoreCards() async {
        let profile = buildTasteProfile()
        var candidates: [iTunesTrack] = []

        if profile.likedCount >= 3 {
            // Smart fetching based on profile
            async let artistTracks = fetchFromTopArtists(profile)
            async let genreTracks = fetchFromTopGenres(profile)
            async let trendingTracks = fetchTrending()
            async let explorationTracks = fetchExploration(profile)

            let all = await [artistTracks, genreTracks, trendingTracks, explorationTracks]
            candidates = all.flatMap { $0 }
        } else {
            // Cold start: popular diverse genres
            let starters = ["pop hits 2025", "rap français 2025", "r&b", "rock indé",
                            "electro", "afrobeats", "k-pop", "jazz chill"]
            for term in starters.shuffled().prefix(4) {
                let tracks = await service.search(term: term, limit: 15)
                candidates.append(contentsOf: tracks)
            }
        }

        // Filter seen, deduplicate, then rank
        let filtered = filterSeen(candidates)
        var uniqueIDs: Set<Int> = Set(cards.map(\.id))
        let unique = filtered.filter { uniqueIDs.insert($0.id).inserted }

        let ranked = rankTracks(unique, profile: profile, count: 15)
        cards.append(contentsOf: ranked)
    }

    private func fetchFromTopArtists(_ profile: TasteProfile) async -> [iTunesTrack] {
        var tracks: [iTunesTrack] = []

        // Use artist IDs for precise lookup, fallback to name search
        for artist in profile.topArtists.prefix(3) {
            if let artistId = artist.ids.first {
                let results = await service.lookupArtist(id: artistId, limit: 15)
                tracks.append(contentsOf: results)
            } else {
                let results = await service.search(term: artist.name, limit: 12)
                tracks.append(contentsOf: results)
            }
        }

        // Also search for "similar" artists by combining genre + recent terms
        if let topGenre = profile.topGenres.first?.name {
            let similar = await service.search(term: "\(topGenre) 2025 new", limit: 15)
            tracks.append(contentsOf: similar)
        }

        return tracks
    }

    private func fetchFromTopGenres(_ profile: TasteProfile) async -> [iTunesTrack] {
        var tracks: [iTunesTrack] = []
        for genre in profile.topGenres.prefix(3) {
            let terms = [genre.name, "\(genre.name) 2025", "\(genre.name) new"]
            if let term = terms.randomElement() {
                let results = await service.search(term: term, limit: 15)
                tracks.append(contentsOf: results)
            }
        }
        return tracks
    }

    private func fetchTrending() async -> [iTunesTrack] {
        let terms = ["top hits 2026", "viral 2025", "trending music", "new releases 2025"]
        guard let term = terms.randomElement() else { return [] }
        return await service.search(term: term, limit: 15)
    }

    private func fetchExploration(_ profile: TasteProfile) async -> [iTunesTrack] {
        let allGenres = ["afrobeats", "k-pop", "jazz", "classical", "reggaeton",
                         "country", "metal", "funk", "soul", "indie", "techno",
                         "drill", "amapiano", "bossa nova", "lo-fi", "gospel",
                         "dancehall", "trap", "house", "grime"]
        let likedGenreNames = Set(profile.topGenres.map(\.name).map { $0.lowercased() })
        let unexplored = allGenres.filter { !likedGenreNames.contains($0) }
        guard let genre = unexplored.randomElement() else { return [] }
        return await service.search(term: "\(genre) 2025", limit: 12)
    }

    // MARK: - For You Sections

    struct ForYouSection: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let icon: String
        let tracks: [iTunesTrack]
        let kind: SectionKind

        enum SectionKind {
            case becauseArtist(String)
            case genreDeepDive(String)
            case newReleases
            case trending
            case moodMix(String)
            case discovery(String)
        }
    }

    func loadForYou() async {
        guard forYouSections.isEmpty else { return }
        isLoadingForYou = true

        let profile = buildTasteProfile()
        var sections: [ForYouSection] = []

        if profile.likedCount >= 3 {
            // "Parce que tu aimes [Artiste]" — 2 sections max, with smart anti-repeat
            let artistSections = await buildArtistSections(profile)
            sections.append(contentsOf: artistSections)

            // "Nouveautés [Genre]" — recent tracks from top genres
            let genreSections = await buildGenreSections(profile)
            sections.append(contentsOf: genreSections)

            // "Ambiance" section — based on energy profile
            if let moodSection = await buildMoodSection(profile) {
                sections.append(moodSection)
            }
        }

        // "Tendances" — always visible
        if let trending = await buildTrendingSection() {
            sections.append(trending)
        }

        // "Découverte" — expand horizons
        if let discovery = await buildDiscoverySection(profile) {
            sections.append(discovery)
        }

        forYouSections = sections
        isLoadingForYou = false
    }

    func refreshForYou() async {
        forYouSections = []
        await loadForYou()
    }

    private func buildArtistSections(_ profile: TasteProfile) async -> [ForYouSection] {
        var sections: [ForYouSection] = []

        for artist in profile.topArtists.prefix(2) {
            // Search for related artists, NOT the same artist
            let relatedTerms = [
                "\(artist.name) similar",
                "\(artist.name) type beat",
            ]
            var allTracks: [iTunesTrack] = []
            for term in relatedTerms {
                let results = await service.search(term: term, limit: 15)
                allTracks.append(contentsOf: results)
            }

            // Filter out the exact same artist to avoid redundancy
            let filtered = filterSeen(allTracks)
                .filter { $0.artistName != artist.name }
                .prefix(8)

            if filtered.count >= 3 {
                sections.append(ForYouSection(
                    title: "Parce que tu aimes",
                    subtitle: artist.name,
                    icon: "heart.fill",
                    tracks: Array(filtered),
                    kind: .becauseArtist(artist.name)
                ))
            }
        }

        return sections
    }

    private func buildGenreSections(_ profile: TasteProfile) async -> [ForYouSection] {
        var sections: [ForYouSection] = []

        for genre in profile.topGenres.prefix(2) {
            let tracks = await service.search(term: "\(genre.name) 2025 nouveauté", limit: 20)
            let ranked = rankTracks(filterSeen(tracks), profile: profile, count: 8)

            if ranked.count >= 3 {
                sections.append(ForYouSection(
                    title: "Nouveautés",
                    subtitle: genre.name,
                    icon: "sparkles",
                    tracks: ranked,
                    kind: .genreDeepDive(genre.name)
                ))
            }
        }

        return sections
    }

    private func buildMoodSection(_ profile: TasteProfile) async -> ForYouSection? {
        let moodLabel: String
        let searchTerm: String

        switch profile.averageEnergy {
        case 0..<0.35:
            moodLabel = "Chill & Relax"
            searchTerm = "chill relax calm"
        case 0.35..<0.55:
            moodLabel = "Easy Listening"
            searchTerm = "feel good vibes"
        case 0.55..<0.75:
            moodLabel = "Bonne humeur"
            searchTerm = "happy upbeat fun"
        default:
            moodLabel = "Énergie pure"
            searchTerm = "workout hype energy"
        }

        var tracks: [iTunesTrack] = []
        for genre in profile.topGenres.prefix(2) {
            let results = await service.search(term: "\(genre.name) \(searchTerm)", limit: 10)
            tracks.append(contentsOf: results)
        }

        let filtered = filterSeen(tracks).shuffled().prefix(8)
        guard filtered.count >= 3 else { return nil }

        return ForYouSection(
            title: "Ambiance",
            subtitle: moodLabel,
            icon: "waveform",
            tracks: Array(filtered),
            kind: .moodMix(moodLabel)
        )
    }

    private func buildTrendingSection() async -> ForYouSection? {
        let terms = ["top hits 2025", "viral 2025", "new music friday", "chart hits"]
        var tracks: [iTunesTrack] = []
        for term in terms.shuffled().prefix(2) {
            let results = await service.search(term: term, limit: 12)
            tracks.append(contentsOf: results)
        }

        let filtered = filterSeen(tracks).shuffled().prefix(8)
        guard filtered.count >= 3 else { return nil }

        return ForYouSection(
            title: "Tendances",
            subtitle: "Les sons du moment",
            icon: "chart.line.uptrend.xyaxis",
            tracks: Array(filtered),
            kind: .trending
        )
    }

    private func buildDiscoverySection(_ profile: TasteProfile) async -> ForYouSection? {
        let allGenres = ["afrobeats", "k-pop", "jazz", "classical", "reggaeton",
                         "country", "metal", "funk", "soul", "indie", "techno",
                         "amapiano", "bossa nova", "lo-fi", "dancehall"]
        let likedNames = Set(profile.topGenres.map(\.name).map { $0.lowercased() })
        let unexplored = allGenres.filter { !likedNames.contains($0) }
        guard let genre = unexplored.randomElement() else { return nil }

        let tracks = await service.search(term: "\(genre) 2025", limit: 15)
        let filtered = filterSeen(tracks).prefix(8)
        guard filtered.count >= 3 else { return nil }

        return ForYouSection(
            title: "Découverte",
            subtitle: genre.capitalized,
            icon: "binoculars.fill",
            tracks: Array(filtered),
            kind: .discovery(genre)
        )
    }

    // MARK: - Core Data

    private func loadSeenIDs() {
        let request = NSFetchRequest<SwipedSongEntity>(entityName: "SwipedSongEntity")
        request.propertiesToFetch = ["id"]
        if let results = try? context.fetch(request) {
            seenIDs = Set(results.compactMap(\.id))
        }
    }

    private func saveSwiped(_ track: iTunesTrack, liked: Bool) {
        let entity = SwipedSongEntity(context: context)
        entity.id = String(track.id)
        entity.title = track.title
        entity.artistName = track.artistName
        entity.albumName = track.albumName
        entity.artworkURL = track.artworkURL(size: 600)?.absoluteString
        entity.previewURL = track.previewURL?.absoluteString
        entity.genre = track.genre
        entity.releaseDate = track.releaseDate
        entity.durationMs = Int64(track.durationMs ?? 0)
        entity.artistId = Int64(track.artistId ?? 0)
        entity.isLiked = liked
        entity.swipedAt = Date()
        try? context.save()
    }

    // MARK: - Helpers

    private func filterSeen(_ tracks: [iTunesTrack]) -> [iTunesTrack] {
        tracks.filter { !seenIDs.contains(String($0.id)) && $0.previewURL != nil }
    }

    /// Reset all data (for testing/debug)
    func resetAll() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "SwipedSongEntity")
        let delete = NSBatchDeleteRequest(fetchRequest: request)
        try? context.execute(delete)
        try? context.save()
        seenIDs.removeAll()
        recentCardArtists.removeAll()
        recentCardGenres.removeAll()
        cards.removeAll()
        forYouSections.removeAll()
    }
}
