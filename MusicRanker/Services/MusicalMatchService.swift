import Foundation

/// Simulated musical compatibility — generates mock profiles based on user taste
/// In a real app, this would connect to a backend
@MainActor
final class MusicalMatchService: ObservableObject {

    static let shared = MusicalMatchService()

    struct MusicalProfile: Identifiable {
        let id: String
        let name: String
        let avatarEmoji: String
        let topGenres: [String]
        let topArtists: [String]
        let energy: Double
        let compatibility: Int // 0-100
        let badge: Badge?
    }

    enum Badge: String {
        case soulmate = "Âme soeur musicale"
        case partyBuddy = "Partner de soirée"
        case chillMate = "Zen buddy"
        case explorer = "Explorateur"
        case genreTwin = "Genre twin"
    }

    @Published var matches: [MusicalProfile] = []
    @Published var isLoading = false

    /// Generate mock matches based on user's taste profile
    func loadMatches(from profile: RecommendationEngine.TasteProfile) async {
        guard matches.isEmpty else { return }
        isLoading = true

        // Simulate network delay
        try? await Task.sleep(nanoseconds: 800_000_000)

        let avatars = ["🎵", "🎸", "🎹", "🎤", "🎧", "🥁", "🎻", "🎺", "🎷", "🪗"]
        let names = [
            "Léa M.", "Hugo D.", "Camille B.", "Lucas F.", "Emma P.",
            "Nathan R.", "Chloé L.", "Théo G.", "Manon S.", "Raphaël V.",
            "Jade T.", "Enzo K.", "Inès W.", "Louis C.", "Sarah A."
        ]

        let userGenres = Set(profile.topGenres.map(\.name))
        let userArtists = Set(profile.topArtists.map(\.name))

        let allGenres = [
            "Pop", "Hip-Hop/Rap", "R&B/Soul", "Rock", "Electronic",
            "Dance", "Jazz", "Classical", "Latin", "K-Pop",
            "Metal", "Alternative", "Country", "Reggae", "Funk"
        ]

        let allArtists = [
            "Drake", "Taylor Swift", "The Weeknd", "Bad Bunny", "Beyoncé",
            "Dua Lipa", "Kendrick Lamar", "Billie Eilish", "Ed Sheeran", "BTS",
            "Post Malone", "Ariana Grande", "Travis Scott", "SZA", "Harry Styles",
            "Stromae", "Aya Nakamura", "Ninho", "Jul", "Angèle"
        ]

        var generated: [MusicalProfile] = []
        let shuffledNames = names.shuffled()

        for i in 0..<min(10, shuffledNames.count) {
            // Generate profile with varying overlap
            let overlapFactor = Double.random(in: 0.2...0.9)

            // Pick genres — some overlap with user, some random
            var genres: [String] = []
            let userGenreArray = Array(userGenres)
            let overlapCount = max(1, Int(Double(userGenreArray.count) * overlapFactor))

            for g in userGenreArray.shuffled().prefix(overlapCount) {
                genres.append(g)
            }
            let remaining = allGenres.filter { !genres.contains($0) }.shuffled()
            genres.append(contentsOf: remaining.prefix(3 - min(genres.count, 3)))
            genres = Array(genres.prefix(3))

            // Pick artists
            var artists: [String] = []
            let userArtistArray = Array(userArtists)
            let artistOverlap = max(0, Int(Double(userArtistArray.count) * overlapFactor))

            for a in userArtistArray.shuffled().prefix(artistOverlap) {
                artists.append(a)
            }
            let remainingArtists = allArtists.filter { !artists.contains($0) }.shuffled()
            artists.append(contentsOf: remainingArtists.prefix(3 - min(artists.count, 3)))
            artists = Array(artists.prefix(3))

            // Compute compatibility based on overlap
            let genreOverlap = Double(Set(genres).intersection(userGenres).count) / max(1, Double(userGenres.count))
            let artistOverlapRatio = Double(Set(artists).intersection(userArtists).count) / max(1, Double(userArtists.count))
            let energy = Double.random(in: 0.2...0.9)
            let energyDiff = abs(energy - profile.averageEnergy)

            let rawCompat = (genreOverlap * 40 + artistOverlapRatio * 35 + (1 - energyDiff) * 25) * 100
            let compatibility = min(99, max(15, Int(rawCompat + Double.random(in: -10...10))))

            // Assign badge
            let badge: Badge?
            if compatibility > 85 { badge = .soulmate }
            else if energy > 0.7 && profile.averageEnergy > 0.7 { badge = .partyBuddy }
            else if energy < 0.35 && profile.averageEnergy < 0.35 { badge = .chillMate }
            else if genreOverlap < 0.3 { badge = .explorer }
            else if genreOverlap > 0.6 { badge = .genreTwin }
            else { badge = nil }

            generated.append(MusicalProfile(
                id: "user_\(i)",
                name: shuffledNames[i],
                avatarEmoji: avatars[i % avatars.count],
                topGenres: genres,
                topArtists: artists,
                energy: energy,
                compatibility: compatibility,
                badge: badge
            ))
        }

        // Sort by compatibility
        matches = generated.sorted { $0.compatibility > $1.compatibility }
        isLoading = false
    }
}
