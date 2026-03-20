import Foundation

// MARK: - Protocol

protocol TrendingMusicProvider: Sendable {
    var name: String { get }
    func fetchTrending(country: String, limit: Int) async throws -> [TrendingTrack]
}

// MARK: - Trending Track (intermediate model before iTunes enrichment)

struct TrendingTrack: Sendable {
    let id: String          // iTunes track ID
    let name: String
    let artistName: String
    let artworkUrl: String?
    let genre: String?
    let releaseDate: String?
}

// MARK: - Apple RSS Models

private struct AppleRSSResponse: Decodable {
    let feed: AppleRSSFeed
}

private struct AppleRSSFeed: Decodable {
    let title: String?
    let country: String?
    let results: [AppleRSSSong]?
}

private struct AppleRSSSong: Decodable {
    let id: String
    let name: String
    let artistName: String
    let artworkUrl100: String?
    let releaseDate: String?
    let genres: [AppleRSSGenre]?
}

private struct AppleRSSGenre: Decodable {
    let name: String
}

// MARK: - Apple RSS Trending Provider (REAL DATA)

final class AppleRSSTrendingProvider: TrendingMusicProvider, @unchecked Sendable {
    let name = "Apple Music Charts"

    private let session: URLSession
    private let baseURL = "https://rss.applemarketingtools.com/api/v2"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTrending(country: String, limit: Int) async throws -> [TrendingTrack] {
        let urlString = "\(baseURL)/\(country)/music/most-played/\(min(limit, 100))/songs.json"
        guard let url = URL(string: urlString) else {
            throw TrendingError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw TrendingError.networkError("Invalid response")
        }

        guard http.statusCode == 200 else {
            throw TrendingError.networkError("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(AppleRSSResponse.self, from: data)

        guard let results = decoded.feed.results, !results.isEmpty else {
            throw TrendingError.emptyResults
        }

        return results.map { song in
            TrendingTrack(
                id: song.id,
                name: song.name,
                artistName: song.artistName,
                artworkUrl: song.artworkUrl100,
                genre: song.genres?.first?.name,
                releaseDate: song.releaseDate
            )
        }
    }
}

// MARK: - iTunes Fallback Provider

final class iTunesFallbackTrendingProvider: TrendingMusicProvider, @unchecked Sendable {
    let name = "iTunes Search Fallback"

    private let service: iTunesService

    init(service: iTunesService = .shared) {
        self.service = service
    }

    func fetchTrending(country: String, limit: Int) async throws -> [TrendingTrack] {
        let year = Calendar.current.component(.year, from: Date())
        let terms = ["top hits \(year)", "hits \(year)", "trending music \(year)"]

        var allTracks: [iTunesTrack] = []
        for term in terms.prefix(2) {
            let results = await service.search(term: term, limit: limit)
            allTracks.append(contentsOf: results)
        }

        // Deduplicate
        var seen: Set<Int> = []
        let unique = allTracks.filter { $0.previewURL != nil && seen.insert($0.id).inserted }

        guard !unique.isEmpty else {
            throw TrendingError.emptyResults
        }

        return unique.prefix(limit).map { track in
            TrendingTrack(
                id: String(track.id),
                name: track.title,
                artistName: track.artistName,
                artworkUrl: track.artworkURL?.absoluteString,
                genre: track.genre,
                releaseDate: track.releaseDate
            )
        }
    }
}

// MARK: - Trending Error

enum TrendingError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case emptyResults
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URL invalide"
        case .networkError(let msg): "Erreur réseau: \(msg)"
        case .emptyResults: "Aucun résultat"
        case .decodingError: "Erreur de décodage"
        }
    }
}

// MARK: - Trending Service (orchestrator)

@MainActor
final class TrendingService: ObservableObject {

    // MARK: - Published State

    enum TrendingState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case error(String)

        static func == (lhs: TrendingState, rhs: TrendingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.loaded, .loaded), (.empty, .empty): true
            case (.error(let a), .error(let b)): a == b
            default: false
            }
        }
    }

    @Published var state: TrendingState = .idle
    @Published var trendingTracks: [iTunesTrack] = []
    @Published var countryName: String = ""
    @Published var countryCode: String = ""
    @Published var sourceName: String = ""

    // MARK: - Private

    private let providers: [TrendingMusicProvider]
    private let itunesService: iTunesService
    private var cachedAt: Date?
    private let cacheDuration: TimeInterval = 1800 // 30 minutes
    private var loadTask: Task<Void, Never>?

    // MARK: - Init

    init(
        providers: [TrendingMusicProvider]? = nil,
        itunesService: iTunesService = .shared
    ) {
        self.itunesService = itunesService
        self.providers = providers ?? [
            AppleRSSTrendingProvider(),
            iTunesFallbackTrendingProvider(service: itunesService)
        ]
        detectCountry()
    }

    // MARK: - Country Detection

    private func detectCountry() {
        let locale = Locale.current
        let code = locale.region?.identifier.lowercased() ?? "fr"
        countryCode = code
        countryName = locale.localizedString(forRegionCode: code.uppercased())?.capitalized ?? "France"
    }

    // MARK: - Load Trending

    func loadTrending(forceRefresh: Bool = false) async {
        // Cache check
        if !forceRefresh,
           let cachedAt,
           !trendingTracks.isEmpty,
           Date().timeIntervalSince(cachedAt) < cacheDuration {
            return
        }

        state = .loading

        for provider in providers {
            do {
                let rawTracks = try await provider.fetchTrending(
                    country: countryCode,
                    limit: 25
                )

                // Enrich with iTunes data (preview URLs)
                let ids = rawTracks.map(\.id)
                let enriched = await itunesService.lookupByIds(ids, country: countryCode)

                if !enriched.isEmpty {
                    trendingTracks = enriched
                    sourceName = provider.name
                    cachedAt = Date()
                    state = .loaded
                    return
                }

                // If enrichment returned nothing, use raw data to build tracks
                let fallbackTracks = rawTracks.compactMap { raw -> iTunesTrack? in
                    guard let id = Int(raw.id) else { return nil }
                    return iTunesTrack(
                        id: id,
                        title: raw.name,
                        artistName: raw.artistName,
                        albumName: nil,
                        artworkURL: raw.artworkUrl.flatMap { URL(string: $0) },
                        previewURL: nil,
                        genre: raw.genre,
                        releaseDate: raw.releaseDate,
                        durationMs: nil,
                        artistId: nil,
                        albumId: nil,
                        trackNumber: nil
                    )
                }

                if !fallbackTracks.isEmpty {
                    trendingTracks = fallbackTracks
                    sourceName = provider.name
                    cachedAt = Date()
                    state = .loaded
                    return
                }

            } catch {
                print("[TrendingService] Provider '\(provider.name)' failed: \(error.localizedDescription)")
                continue // Try next provider
            }
        }

        // All providers failed
        if trendingTracks.isEmpty {
            state = .empty
        } else {
            state = .error("Impossible de rafraîchir les tendances")
        }
    }

    func refresh() async {
        await loadTrending(forceRefresh: true)
    }
}
