import Foundation

// MARK: - Protocol for testability

protocol MusicSearchService: Sendable {
    func search(term: String, limit: Int) async -> [iTunesTrack]
    func lookupArtist(id: Int, limit: Int) async -> [iTunesTrack]
}

// MARK: - iTunes Search API Implementation

final class iTunesService: MusicSearchService, @unchecked Sendable {

    static let shared = iTunesService()

    private let session: URLSession
    private let baseURL = "https://itunes.apple.com"
    private let country = "fr"

    /// Thread-safe cache with NSLock
    private var cache: [String: (tracks: [iTunesTrack], date: Date)] = [:]
    private let cacheLock = NSLock()
    private let cacheDuration: TimeInterval = 300

    /// Rate limiting: minimum interval between requests
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 0.3
    private let rateLock = NSLock()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search

    func search(term: String, limit: Int = 25) async -> [iTunesTrack] {
        let cacheKey = "search:\(term):\(limit)"

        // Check cache (thread-safe)
        cacheLock.lock()
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.date) < cacheDuration {
            cacheLock.unlock()
            return cached.tracks
        }
        cacheLock.unlock()

        guard var components = URLComponents(string: "\(baseURL)/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]

        let tracks = await fetch(url: components.url)

        cacheLock.lock()
        cache[cacheKey] = (tracks, Date())
        cacheLock.unlock()

        return tracks
    }

    // MARK: - Artist Lookup

    func lookupArtist(id: Int, limit: Int = 20) async -> [iTunesTrack] {
        let cacheKey = "artist:\(id):\(limit)"

        cacheLock.lock()
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.date) < cacheDuration {
            cacheLock.unlock()
            return cached.tracks
        }
        cacheLock.unlock()

        guard var components = URLComponents(string: "\(baseURL)/lookup") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ]

        let tracks = await fetch(url: components.url)

        cacheLock.lock()
        cache[cacheKey] = (tracks, Date())
        cacheLock.unlock()

        return tracks
    }

    // MARK: - Bulk Lookup by IDs

    /// Lookup multiple tracks by their iTunes IDs in a single request
    func lookupByIds(_ ids: [String], country: String = "fr") async -> [iTunesTrack] {
        guard !ids.isEmpty else { return [] }

        let idsString = ids.prefix(50).joined(separator: ",")
        let cacheKey = "bulk:\(idsString):\(country)"

        cacheLock.lock()
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.date) < cacheDuration {
            cacheLock.unlock()
            return cached.tracks
        }
        cacheLock.unlock()

        guard var components = URLComponents(string: "\(baseURL)/lookup") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "id", value: idsString),
            URLQueryItem(name: "country", value: country),
        ]

        let tracks = await fetch(url: components.url)

        cacheLock.lock()
        cache[cacheKey] = (tracks, Date())
        cacheLock.unlock()

        return tracks
    }

    // MARK: - Private

    private func fetch(url: URL?) async -> [iTunesTrack] {
        guard let url else { return [] }

        // Simple rate limiting
        await respectRateLimit()

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

    private func respectRateLimit() async {
        rateLock.lock()
        let timeSinceLast = Date().timeIntervalSince(lastRequestTime)
        let waitTime = max(0, minRequestInterval - timeSinceLast)
        lastRequestTime = Date().addingTimeInterval(waitTime)
        rateLock.unlock()

        if waitTime > 0 {
            try? await Task.sleep(for: .milliseconds(Int(waitTime * 1000)))
        }
    }

    /// Clear all cached data
    func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }
}
