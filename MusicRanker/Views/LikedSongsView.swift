import SwiftUI
import CoreData

// MARK: - Sort Options

enum LikedSongsSortOption: String, CaseIterable {
    case recent = "Récents"
    case artist = "Artiste"
    case genre = "Genre"
    case title = "Titre"

    var icon: String {
        switch self {
        case .recent: "clock"
        case .artist: "person"
        case .genre: "guitars"
        case .title: "textformat.abc"
        }
    }
}

struct LikedSongsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var playlistManager: PlaylistManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SwipedSongEntity.swipedAt, ascending: false)],
        predicate: NSPredicate(format: "isLiked == YES"),
        animation: .none
    )
    private var likedSongs: FetchedResults<SwipedSongEntity>

    @State private var searchText = ""
    @State private var sortOption: LikedSongsSortOption = .recent
    @State private var selectedGenreFilter: String?
    @State private var playlistTarget: iTunesTrack?

    // MARK: - Computed

    private var allGenres: [String] {
        var counts: [String: Int] = [:]
        for song in likedSongs {
            if let genre = song.genre, !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private var filteredAndSortedSongs: [SwipedSongEntity] {
        var songs = Array(likedSongs)

        if let genre = selectedGenreFilter {
            songs = songs.filter { $0.genre == genre }
        }

        if !searchText.isEmpty {
            songs = songs.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.artistName ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.genre ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOption {
        case .recent:
            songs.sort { ($0.swipedAt ?? .distantPast) > ($1.swipedAt ?? .distantPast) }
        case .artist:
            songs.sort { ($0.artistName ?? "") < ($1.artistName ?? "") }
        case .genre:
            songs.sort { ($0.genre ?? "") < ($1.genre ?? "") }
        case .title:
            songs.sort { ($0.title ?? "") < ($1.title ?? "") }
        }

        return songs
    }

    var body: some View {
        Group {
            if likedSongs.isEmpty {
                emptyState
            } else if filteredAndSortedSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                songsList
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher dans tes likes...")
        .sheet(item: $playlistTarget) { track in
            AddToPlaylistSheet(track: track)
                .environmentObject(playlistManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Songs List

    private var songsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Compact header: count + shuffle inline
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                // Genre chips (only if multiple)
                if allGenres.count > 1 {
                    genreFilterChips
                        .padding(.bottom, 6)
                }

                // Sort bar
                sortBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Track list
                LazyVStack(spacing: 0) {
                    ForEach(filteredAndSortedSongs, id: \.objectID) { song in
                        LikedSongRow(song: song)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.impact(.light)
                                playSong(song)
                            }
                            .contextMenu {
                                if song.previewURL != nil {
                                    Button {
                                        playSong(song)
                                    } label: {
                                        Label("Écouter", systemImage: "play.fill")
                                    }
                                }

                                Button {
                                    playlistTarget = songToTrack(song)
                                } label: {
                                    Label("Ajouter à une playlist", systemImage: "text.badge.plus")
                                }

                                // External platforms
                                Menu("Ouvrir dans...") {
                                    ForEach(MusicPlatform.allCases) { platform in
                                        Button {
                                            ExternalMusicOpener.open(
                                                platform: platform,
                                                title: song.title ?? "",
                                                artist: song.artistName ?? ""
                                            )
                                        } label: {
                                            Label(platform.rawValue, systemImage: platform.icon)
                                        }
                                    }
                                }

                                Divider()

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

                        if song.objectID != filteredAndSortedSongs.last?.objectID {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Header Bar (compact: count + top genres + shuffle)

    private var headerBar: some View {
        HStack(spacing: 0) {
            // Count
            Text("\(likedSongs.count)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.green)
            Text(" like\(likedSongs.count > 1 ? "s" : "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Top genres as dots
            let genres = topGenres(2)
            if !genres.isEmpty {
                Text("  ·  ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    if genre != genres.last {
                        Text(", ")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Shuffle button
            Button {
                HapticManager.impact(.medium)
                shufflePlay()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shuffle")
                        .font(.caption2.weight(.bold))
                    Text("Mix")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.tint, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Genre Filter

    private var genreFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "Tout", isSelected: selectedGenreFilter == nil) {
                    withAnimation(.spring(duration: 0.25)) { selectedGenreFilter = nil }
                }

                ForEach(allGenres, id: \.self) { genre in
                    FilterChip(label: genre, isSelected: selectedGenreFilter == genre) {
                        withAnimation(.spring(duration: 0.25)) {
                            selectedGenreFilter = selectedGenreFilter == genre ? nil : genre
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(LikedSongsSortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.spring(duration: 0.25)) { sortOption = option }
                    } label: {
                        Label(option.rawValue, systemImage: option.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2.weight(.semibold))
                    Text(sortOption.rawValue)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(filteredAndSortedSongs.count) titre\(filteredAndSortedSongs.count > 1 ? "s" : "")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.08))
                    .frame(width: 90, height: 90)
                Image(systemName: "heart")
                    .font(.system(size: 36))
                    .foregroundStyle(.green.opacity(0.4))
            }
            Text("Aucun like")
                .font(.title3.weight(.semibold))
            Text("Swipe a droite dans Decouvrir\npour sauvegarder tes morceaux.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func songToTrack(_ song: SwipedSongEntity) -> iTunesTrack {
        iTunesTrack(
            id: Int(song.id ?? "0") ?? 0,
            title: song.title ?? "",
            artistName: song.artistName ?? "",
            albumName: song.albumName,
            artworkURL: song.artworkURL.flatMap { URL(string: $0) },
            previewURL: song.previewURL.flatMap { URL(string: $0) },
            genre: song.genre,
            releaseDate: song.releaseDate,
            durationMs: Int(song.durationMs),
            artistId: Int(song.artistId),
            albumId: nil,
            trackNumber: nil
        )
    }

    private func playSong(_ song: SwipedSongEntity) {
        guard song.previewURL != nil else { return }
        player.forcePlay(track: songToTrack(song))
    }

    private func shufflePlay() {
        let songs = filteredAndSortedSongs
        guard !songs.isEmpty else { return }
        let random = songs.randomElement()!
        playSong(random)
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

// MARK: - Filter Chip (reusable)

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liked Song Row (compact)

struct LikedSongRow: View {
    let song: SwipedSongEntity
    @EnvironmentObject private var player: AudioPlayerManager

    private var trackId: Int {
        Int(song.id ?? "0") ?? 0
    }

    private var isPlaying: Bool {
        player.isCurrentlyPlaying(id: trackId)
    }

    var body: some View {
        HStack(spacing: 10) {
            AsyncArtwork(
                url: song.artworkURL.flatMap { URL(string: $0) },
                size: 44,
                radius: 8
            )
            .overlay {
                if isPlaying {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.3))
                    Image(systemName: "waveform")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? "Titre inconnu")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(song.artistName ?? "Artiste")
                    if let genre = song.genre, !genre.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
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
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        }
    }
}
