import UIKit

// MARK: - Protocol

protocol ExternalMusicProvider {
    var name: String { get }
    var icon: String { get }
    var color: String { get } // Hex color
    func buildURL(title: String, artist: String) -> URL?
    func canOpen() -> Bool
}

// MARK: - Provider Manager

enum MusicPlatform: String, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case deezer = "Deezer"
    case youtube = "YouTube"

    var id: String { rawValue }

    var provider: ExternalMusicProvider {
        switch self {
        case .appleMusic: AppleMusicProvider()
        case .spotify: SpotifyProvider()
        case .deezer: DeezerProvider()
        case .youtube: YouTubeProvider()
        }
    }

    var icon: String {
        switch self {
        case .appleMusic: "applelogo"
        case .spotify: "antenna.radiowaves.left.and.right"
        case .deezer: "waveform"
        case .youtube: "play.rectangle.fill"
        }
    }

    var systemColor: String {
        switch self {
        case .appleMusic: "FA2D55"
        case .spotify: "1DB954"
        case .deezer: "A238FF"
        case .youtube: "FF0000"
        }
    }
}

// MARK: - Apple Music Provider

struct AppleMusicProvider: ExternalMusicProvider {
    let name = "Apple Music"
    let icon = "applelogo"
    let color = "FA2D55"

    func buildURL(title: String, artist: String) -> URL? {
        let query = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Try app URL first, system handles fallback to web
        if canOpen() {
            return URL(string: "music://music.apple.com/search?term=\(query)")
        }
        return URL(string: "https://music.apple.com/search?term=\(query)")
    }

    func canOpen() -> Bool {
        URL(string: "music://").flatMap { UIApplication.shared.canOpenURL($0) } ?? false
    }
}

// MARK: - Spotify Provider

struct SpotifyProvider: ExternalMusicProvider {
    let name = "Spotify"
    let icon = "antenna.radiowaves.left.and.right"
    let color = "1DB954"

    func buildURL(title: String, artist: String) -> URL? {
        let query = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if canOpen() {
            return URL(string: "spotify:search:\(query)")
        }
        return URL(string: "https://open.spotify.com/search/\(query)")
    }

    func canOpen() -> Bool {
        URL(string: "spotify://").flatMap { UIApplication.shared.canOpenURL($0) } ?? false
    }
}

// MARK: - Deezer Provider

struct DeezerProvider: ExternalMusicProvider {
    let name = "Deezer"
    let icon = "waveform"
    let color = "A238FF"

    func buildURL(title: String, artist: String) -> URL? {
        let query = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if canOpen() {
            return URL(string: "deezer://www.deezer.com/search/\(query)")
        }
        return URL(string: "https://www.deezer.com/search/\(query)")
    }

    func canOpen() -> Bool {
        URL(string: "deezer://").flatMap { UIApplication.shared.canOpenURL($0) } ?? false
    }
}

// MARK: - YouTube Provider

struct YouTubeProvider: ExternalMusicProvider {
    let name = "YouTube"
    let icon = "play.rectangle.fill"
    let color = "FF0000"

    func buildURL(title: String, artist: String) -> URL? {
        let query = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if canOpen() {
            return URL(string: "youtube://www.youtube.com/results?search_query=\(query)")
        }
        return URL(string: "https://www.youtube.com/results?search_query=\(query)")
    }

    func canOpen() -> Bool {
        URL(string: "youtube://").flatMap { UIApplication.shared.canOpenURL($0) } ?? false
    }
}

// MARK: - Open Helper

@MainActor
enum ExternalMusicOpener {
    static func open(platform: MusicPlatform, title: String, artist: String) {
        guard let url = platform.provider.buildURL(title: title, artist: artist) else { return }
        UIApplication.shared.open(url)
    }
}
