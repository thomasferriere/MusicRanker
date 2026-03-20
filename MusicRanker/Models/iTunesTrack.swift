import Foundation

// MARK: - iTunes API Response

struct iTunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [iTunesTrack]
}

// MARK: - Track Model

struct iTunesTrack: Identifiable, Decodable, Equatable, Hashable {
    let id: Int
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
    let previewURL: URL?
    let genre: String?
    let releaseDate: String?
    let durationMs: Int?
    let artistId: Int?
    let albumId: Int?
    let trackNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case title = "trackName"
        case artistName
        case albumName = "collectionName"
        case artworkURL = "artworkUrl100"
        case previewURL = "previewUrl"
        case genre = "primaryGenreName"
        case releaseDate
        case durationMs = "trackTimeMillis"
        case artistId
        case albumId = "collectionId"
        case trackNumber
    }

    /// Artwork URL resized to a custom dimension
    func artworkURL(size: Int) -> URL? {
        guard let base = artworkURL else { return nil }
        let resized = base.absoluteString
            .replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)bb")
        return URL(string: resized)
    }

    /// Formatted duration string (e.g. "3:24")
    var formattedDuration: String? {
        guard let ms = durationMs else { return nil }
        let seconds = ms / 1000
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Parsed release year (e.g. "2024")
    var releaseYear: String? {
        guard let dateStr = releaseDate else { return nil }
        return String(dateStr.prefix(4))
    }

    /// Full formatted release date
    var formattedReleaseDate: String? {
        guard let dateStr = releaseDate else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let display = DateFormatter()
            display.dateStyle = .long
            display.locale = Locale(identifier: "fr_FR")
            return display.string(from: date)
        }
        // Fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateStr) {
            let display = DateFormatter()
            display.dateStyle = .long
            display.locale = Locale(identifier: "fr_FR")
            return display.string(from: date)
        }
        return String(dateStr.prefix(10))
    }

    /// Age of the track in days (for recency scoring)
    var ageDays: Int? {
        guard let dateStr = releaseDate else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: dateStr)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateStr)
        }
        guard let d = date else { return nil }
        return Calendar.current.dateComponents([.day], from: d, to: Date()).day
    }
}
