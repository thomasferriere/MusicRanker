import SwiftUI
import CoreData

struct LikedSongsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var player: AudioPlayerManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SwipedSongEntity.swipedAt, ascending: false)],
        predicate: NSPredicate(format: "isLiked == YES"),
        animation: .default
    )
    private var likedSongs: FetchedResults<SwipedSongEntity>

    @State private var searchText = ""
    @State private var selectedTrack: iTunesTrack?

    private var filteredSongs: [SwipedSongEntity] {
        guard !searchText.isEmpty else { return Array(likedSongs) }
        return likedSongs.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.artistName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.genre ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if likedSongs.isEmpty {
                emptyState
            } else if filteredSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                songsList
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher dans tes likes...")
    }

    // MARK: - Songs List

    private var songsList: some View {
        ScrollView {
            // Stats header
            likeStats
                .padding(.horizontal, 16)
                .padding(.top, 8)

            LazyVStack(spacing: 0) {
                ForEach(filteredSongs, id: \.objectID) { song in
                    LikedSongRow(song: song)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.impact(.light)
                            Task { await playSong(song) }
                        }
                        .contextMenu {
                            if song.previewURL != nil {
                                Button {
                                    Task { await playSong(song) }
                                } label: {
                                    Label("Écouter", systemImage: "play.fill")
                                }
                            }

                            Button(role: .destructive) {
                                HapticManager.impact(.rigid)
                                withAnimation {
                                    viewContext.delete(song)
                                    try? viewContext.save()
                                }
                            } label: {
                                Label("Retirer", systemImage: "heart.slash")
                            }
                        }

                    if song.objectID != filteredSongs.last?.objectID {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }

    // MARK: - Stats

    private var likeStats: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("\(likedSongs.count)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.green)
                Text("likes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Genre breakdown
            let genres = topGenres(3)
            if !genres.isEmpty {
                Divider().frame(height: 32)
                HStack(spacing: 6) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.1), in: Capsule())
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Aucun like")
                .font(.title3.weight(.semibold))
            Text("Swipe à droite dans Découvrir pour sauvegarder tes morceaux préférés.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func playSong(_ song: SwipedSongEntity) async {
        guard let urlStr = song.previewURL, let url = URL(string: urlStr) else { return }
        let track = iTunesTrack(
            id: Int(song.id ?? "0") ?? 0,
            title: song.title ?? "",
            artistName: song.artistName ?? "",
            albumName: song.albumName,
            artworkURL: song.artworkURL.flatMap { URL(string: $0) },
            previewURL: url,
            genre: song.genre,
            releaseDate: song.releaseDate,
            durationMs: Int(song.durationMs),
            artistId: Int(song.artistId),
            albumId: nil,
            trackNumber: nil
        )
        await player.forcePlay(track: track)
    }

    private func topGenres(_ count: Int) -> [String] {
        var genreCounts: [String: Int] = [:]
        for song in likedSongs {
            if let genre = song.genre, !genre.isEmpty {
                genreCounts[genre, default: 0] += 1
            }
        }
        return genreCounts.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }
}

// MARK: - Liked Song Row

struct LikedSongRow: View {
    let song: SwipedSongEntity
    @EnvironmentObject private var player: AudioPlayerManager

    private var isPlaying: Bool {
        let id = Int(song.id ?? "0") ?? 0
        return player.isCurrentlyPlaying(id: id)
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncArtwork(
                url: song.artworkURL.flatMap { URL(string: $0) },
                size: 48,
                radius: 10
            )
            .overlay {
                if isPlaying {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity(0.3))
                    Image(systemName: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title ?? "Titre inconnu")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(song.artistName ?? "Artiste")
                    if let genre = song.genre, !genre.isEmpty {
                        Text("·")
                        Text(genre)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        }
    }
}
