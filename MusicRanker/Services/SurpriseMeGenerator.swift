import Foundation

/// Generates smart playlists based on user taste profile, mood, and listening history
@MainActor
final class SurpriseMeGenerator {

    static let shared = SurpriseMeGenerator()

    /// Generate a smart playlist
    func generate(
        profile: RecommendationEngine.TasteProfile,
        mood: MoodManager.Mood,
        count: Int = 15
    ) async -> (name: String, tracks: [iTunesTrack]) {
        let service = iTunesService.shared
        let year = Calendar.current.component(.year, from: Date())
        var allTracks: [iTunesTrack] = []

        // Build search strategy based on mood + taste
        let searches = buildSearchStrategy(profile: profile, mood: mood, year: year)

        // Execute searches in parallel batches
        await withTaskGroup(of: [iTunesTrack].self) { group in
            for term in searches {
                group.addTask {
                    await service.search(term: term, limit: 12)
                }
            }
            for await results in group {
                allTracks.append(contentsOf: results)
            }
        }

        // Filter and score
        let filtered = allTracks
            .filter { $0.previewURL != nil }
            .reduce(into: [Int: iTunesTrack]()) { dict, track in
                dict[track.id] = track // deduplicate
            }
            .values
            .shuffled()

        // Take best tracks
        let selected = Array(filtered.prefix(count))

        // Generate playlist name
        let name = generateName(mood: mood, profile: profile)

        return (name: name, tracks: selected)
    }

    private func buildSearchStrategy(
        profile: RecommendationEngine.TasteProfile,
        mood: MoodManager.Mood,
        year: Int
    ) -> [String] {
        var terms: [String] = []

        // Mood-based terms
        if mood != .none {
            terms.append(contentsOf: mood.searchTerms.shuffled().prefix(2))
        }

        // Taste-based terms
        for genre in profile.topGenres.prefix(2) {
            if mood != .none {
                // Mix genre with mood
                let moodWord = mood.searchTerms.first?.components(separatedBy: " ").first ?? ""
                terms.append("\(genre.name) \(moodWord) \(year)")
            } else {
                terms.append("\(genre.name) \(year) new")
            }
        }

        // Artist-based discovery
        for artist in profile.topArtists.prefix(2) {
            terms.append("\(artist.name) similar")
        }

        // Energy-based
        let energyTerm: String
        switch profile.averageEnergy {
        case 0..<0.35: energyTerm = "chill smooth vibes"
        case 0.35..<0.55: energyTerm = "feel good easy listening"
        case 0.55..<0.75: energyTerm = "upbeat happy music"
        default: energyTerm = "energy hype workout"
        }
        terms.append(energyTerm)

        // Wild card for discovery
        let wildcards = ["hidden gems \(year)", "underground \(year)", "indie discovery", "fresh music \(year)"]
        terms.append(wildcards.randomElement()!)

        return terms
    }

    private func generateName(mood: MoodManager.Mood, profile: RecommendationEngine.TasteProfile) -> String {
        let moodNames: [MoodManager.Mood: [String]] = [
            .chill: ["Zen Flow", "Calm Waves", "Easy Breeze"],
            .party: ["Night Out", "Dance Floor", "Let's Go"],
            .workout: ["Beast Mode", "No Limits", "Push It"],
            .love: ["Heartstrings", "Velvet", "Tender"],
            .night: ["After Dark", "Midnight", "Nocturn"],
            .nostalgia: ["Rewind", "Golden Days", "Throwback"],
            .none: ["Surprise Mix", "For You", "Fresh Picks"],
        ]

        let options = moodNames[mood] ?? ["Mix"]
        let base = options.randomElement() ?? "Mix"

        if let genre = profile.topGenres.first?.name {
            return "\(base) · \(genre)"
        }
        return base
    }
}
