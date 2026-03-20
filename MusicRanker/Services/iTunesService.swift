import Foundation

// MARK: - Protocol for testability

protocol MusicSearchService {
    func search(term: String, limit: Int) async -> [iTunesTrack]
    func lookupArtist(id: Int, limit: Int) async -> [iTunesTrack]
}

// MARK: - iTunes Search API Implementation

final class iTunesService: MusicSearchService {

    static let shared = iTunesService()

    private let session: URLSession
    private let baseURL = "https://itunes.apple.com"
    private let country = "fr"

    /// Simple in-memory cache to avoid redundant requests
    private var cache: [String: (tracks: [iTunesTrack], date: Date)] = [:]
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search

    func search(term: String, limit: Int = 25) async -> [iTunesTrack] {
        let cacheKey = "search:\(term):\(limit)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.date) < cacheDuration {
            return cached.tracks
        }

        guard var components = URLComponents(string: "\(baseURL)/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]

        let tracks = await fetch(url: components.url)
        cache[cacheKey] = (tracks, Date())
        return tracks
    }

    // MARK: - Artist Lookup

    func lookupArtist(id: Int, limit: Int = 20) async -> [iTunesTrack] {
        let cacheKey = "artist:\(id):\(limit)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.date) < cacheDuration {
            return cached.tracks
        }

        guard var components = URLComponents(string: "\(baseURL)/lookup") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]

        let tracks = await fetch(url: components.url)
        cache[cacheKey] = (tracks, Date())
        return tracks
    }

    // MARK: - Private

    private func fetch(url: URL?) async -> [iTunesTrack] {
        guard let url else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
            return decoded.results.filter { $0.previewURL != nil }
        } catch {
            print("[iTunesService] Error: \(error.localizedDescription)")
            return []
        }
    }

    /// Clear all cached data
    func clearCache() {
        cache.removeAll()
    }
}
