import Foundation
import CoreData
import SwiftUI

/// Manages internal playlists (CRUD) using Core Data
@MainActor
final class PlaylistManager: ObservableObject {

    // MARK: - Published

    @Published var playlists: [Playlist] = []

    // MARK: - Private

    private let context: NSManagedObjectContext

    // MARK: - Model

    struct Playlist: Identifiable, Equatable {
        let id: String
        var name: String
        var tracks: [PlaylistTrack]
        var createdAt: Date

        var trackCount: Int { tracks.count }
    }

    struct PlaylistTrack: Identifiable, Equatable, Hashable {
        let id: String // track ID
        let title: String
        let artistName: String
        let albumName: String?
        let artworkURL: String?
        let previewURL: String?
        let genre: String?
        let releaseDate: String?
        let durationMs: Int
        let artistId: Int
        let addedAt: Date
        let orderIndex: Int

        func toiTunesTrack() -> iTunesTrack {
            iTunesTrack(
                id: Int(id) ?? 0,
                title: title,
                artistName: artistName,
                albumName: albumName,
                artworkURL: artworkURL.flatMap { URL(string: $0) },
                previewURL: previewURL.flatMap { URL(string: $0) },
                genre: genre,
                releaseDate: releaseDate,
                durationMs: durationMs,
                artistId: artistId,
                albumId: nil,
                trackNumber: nil
            )
        }
    }

    // MARK: - Persistence Keys

    private static let playlistsKey = "user_playlists_v3"

    // MARK: - Init

    init(context: NSManagedObjectContext) {
        self.context = context
        loadPlaylists()
    }

    // MARK: - CRUD

    func createPlaylist(name: String) {
        let playlist = Playlist(
            id: UUID().uuidString,
            name: name,
            tracks: [],
            createdAt: Date()
        )
        playlists.insert(playlist, at: 0)
        savePlaylists()
    }

    func renamePlaylist(id: String, newName: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = newName
        savePlaylists()
    }

    func deletePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func addTrack(_ track: iTunesTrack, to playlistId: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }

        // Prevent duplicates
        let trackId = String(track.id)
        guard !playlists[index].tracks.contains(where: { $0.id == trackId }) else { return }

        let playlistTrack = PlaylistTrack(
            id: trackId,
            title: track.title,
            artistName: track.artistName,
            albumName: track.albumName,
            artworkURL: track.artworkURL(size: 600)?.absoluteString,
            previewURL: track.previewURL?.absoluteString,
            genre: track.genre,
            releaseDate: track.releaseDate,
            durationMs: track.durationMs ?? 0,
            artistId: track.artistId ?? 0,
            addedAt: Date(),
            orderIndex: playlists[index].tracks.count
        )

        playlists[index].tracks.append(playlistTrack)
        savePlaylists()
    }

    func removeTrack(trackId: String, from playlistId: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].tracks.removeAll { $0.id == trackId }
        savePlaylists()
    }

    func isTrackInPlaylist(trackId: Int, playlistId: String) -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistId }) else { return false }
        return playlist.tracks.contains { $0.id == String(trackId) }
    }

    // MARK: - Persistence (UserDefaults + Codable)

    private func savePlaylists() {
        let data = playlists.map { playlist in
            [
                "id": playlist.id,
                "name": playlist.name,
                "createdAt": ISO8601DateFormatter().string(from: playlist.createdAt),
                "tracks": playlist.tracks.map { track in
                    [
                        "id": track.id,
                        "title": track.title,
                        "artistName": track.artistName,
                        "albumName": track.albumName ?? "",
                        "artworkURL": track.artworkURL ?? "",
                        "previewURL": track.previewURL ?? "",
                        "genre": track.genre ?? "",
                        "releaseDate": track.releaseDate ?? "",
                        "durationMs": String(track.durationMs),
                        "artistId": String(track.artistId),
                        "addedAt": ISO8601DateFormatter().string(from: track.addedAt),
                        "orderIndex": String(track.orderIndex)
                    ]
                }
            ] as [String: Any]
        }

        if let json = try? JSONSerialization.data(withJSONObject: data) {
            UserDefaults.standard.set(json, forKey: Self.playlistsKey)
        }
    }

    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: Self.playlistsKey),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        let formatter = ISO8601DateFormatter()

        playlists = array.compactMap { dict -> Playlist? in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let dateStr = dict["createdAt"] as? String,
                  let createdAt = formatter.date(from: dateStr) else { return nil }

            let tracksArray = (dict["tracks"] as? [[String: String]]) ?? []
            let tracks = tracksArray.compactMap { t -> PlaylistTrack? in
                guard let tid = t["id"],
                      let title = t["title"],
                      let artist = t["artistName"] else { return nil }
                return PlaylistTrack(
                    id: tid,
                    title: title,
                    artistName: artist,
                    albumName: t["albumName"]?.isEmpty == true ? nil : t["albumName"],
                    artworkURL: t["artworkURL"]?.isEmpty == true ? nil : t["artworkURL"],
                    previewURL: t["previewURL"]?.isEmpty == true ? nil : t["previewURL"],
                    genre: t["genre"]?.isEmpty == true ? nil : t["genre"],
                    releaseDate: t["releaseDate"]?.isEmpty == true ? nil : t["releaseDate"],
                    durationMs: Int(t["durationMs"] ?? "0") ?? 0,
                    artistId: Int(t["artistId"] ?? "0") ?? 0,
                    addedAt: formatter.date(from: t["addedAt"] ?? "") ?? Date(),
                    orderIndex: Int(t["orderIndex"] ?? "0") ?? 0
                )
            }

            return Playlist(id: id, name: name, tracks: tracks, createdAt: createdAt)
        }
    }
}
