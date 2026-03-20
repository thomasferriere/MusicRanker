import SwiftUI
import CoreData

/// Bibliotheque premium -- Likes + Playlists
struct LibraryView: View {
    @State private var selectedSection: LibrarySection = .likes

    enum LibrarySection: String, CaseIterable {
        case likes = "Likes"
        case playlists = "Playlists"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segment picker (compact)
            Picker("Section", selection: $selectedSection) {
                ForEach(LibrarySection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            switch selectedSection {
            case .likes:
                LikedSongsView()
            case .playlists:
                PlaylistsView()
            }
        }
    }
}

// MARK: - Playlists View (premium)

struct PlaylistsView: View {
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var editingPlaylistId: String?
    @State private var editName = ""
    @State private var selectedPlaylist: PlaylistManager.Playlist?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        Group {
            if playlistManager.playlists.isEmpty && !showNewPlaylist {
                emptyState
            } else {
                playlistsList
            }
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .environmentObject(playlistManager)
                .environmentObject(player)
        }
        .alert("Renommer la playlist", isPresented: .init(
            get: { editingPlaylistId != nil },
            set: { if !$0 { editingPlaylistId = nil } }
        )) {
            TextField("Nom", text: $editName)
            Button("Annuler", role: .cancel) { editingPlaylistId = nil }
            Button("Renommer") {
                if let id = editingPlaylistId {
                    playlistManager.renamePlaylist(id: id, newName: editName)
                }
                editingPlaylistId = nil
            }
        }
    }

    // MARK: - Empty State (premium)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.tint.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "music.note.list")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint.opacity(0.5))
            }

            Text("Aucune playlist")
                .font(.title3.weight(.semibold))

            Text("Cree ta premiere playlist pour\norganiser tes morceaux preferes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation(.spring(duration: 0.3)) { showNewPlaylist = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("Creer une playlist")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 11)
                .background(.tint, in: Capsule())
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Playlists List (grid layout)

    private var playlistsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // Create button (compact)
                createButton
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // Create field
                if showNewPlaylist {
                    createField
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Stats line
                if !playlistManager.playlists.isEmpty {
                    statsLine
                        .padding(.horizontal, 20)
                }

                // Grid of playlists
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(playlistManager.playlists) { playlist in
                        PlaylistGridCard(playlist: playlist) {
                            selectedPlaylist = playlist
                        }
                        .contextMenu {
                            playlistContextMenu(playlist: playlist)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 100)
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { showNewPlaylist.toggle() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.tint.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.tint)
                }
                Text("Nouvelle playlist")
                    .font(.callout.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Field

    private var createField: some View {
        HStack(spacing: 8) {
            TextField("Nom de la playlist", text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            Button("Creer") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                playlistManager.createPlaylist(name: name)
                newPlaylistName = ""
                showNewPlaylist = false
                HapticManager.notification(.success)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Stats Line

    private var statsLine: some View {
        HStack(spacing: 0) {
            let totalTracks = playlistManager.playlists.reduce(0) { $0 + $1.trackCount }
            Text("\(playlistManager.playlists.count) playlist\(playlistManager.playlists.count > 1 ? "s" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(" · ")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("\(totalTracks) titre\(totalTracks > 1 ? "s" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func playlistContextMenu(playlist: PlaylistManager.Playlist) -> some View {
        Button {
            if let track = playlist.tracks.first {
                player.forcePlay(track: track.toiTunesTrack())
            }
        } label: {
            Label("Lire", systemImage: "play.fill")
        }
        .disabled(playlist.tracks.isEmpty)

        Button {
            if let random = playlist.tracks.randomElement() {
                player.forcePlay(track: random.toiTunesTrack())
            }
        } label: {
            Label("Lecture aleatoire", systemImage: "shuffle")
        }
        .disabled(playlist.tracks.isEmpty)

        Divider()

        Button {
            editingPlaylistId = playlist.id
            editName = playlist.name
        } label: {
            Label("Renommer", systemImage: "pencil")
        }

        Button(role: .destructive) {
            HapticManager.notification(.warning)
            withAnimation { playlistManager.deletePlaylist(id: playlist.id) }
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }
}

// MARK: - Playlist Grid Card (premium, square)

struct PlaylistGridCard: View {
    let playlist: PlaylistManager.Playlist
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Square artwork mosaic
                artworkMosaic
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text("\(playlist.trackCount) titre\(playlist.trackCount > 1 ? "s" : "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let dominantArtist = findDominantArtist() {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(dominantArtist)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Artwork Mosaic

    @ViewBuilder
    private var artworkMosaic: some View {
        let artworks = playlist.tracks.prefix(4).compactMap { $0.artworkURL }

        if artworks.isEmpty {
            // Empty placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                VStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Vide")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if artworks.count < 4 {
            // Single / partial artwork
            AsyncImage(url: URL(string: artworks[0])) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.15)
                }
            }
        } else {
            // 2x2 grid mosaic
            VStack(spacing: 1.5) {
                HStack(spacing: 1.5) {
                    mosaicTile(artworks[0])
                    mosaicTile(artworks[1])
                }
                HStack(spacing: 1.5) {
                    mosaicTile(artworks[2])
                    mosaicTile(artworks[3])
                }
            }
        }
    }

    private func mosaicTile(_ urlString: String) -> some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            if case .success(let img) = phase {
                img.resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Dominant Artist

    private func findDominantArtist() -> String? {
        guard !playlist.tracks.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for track in playlist.tracks {
            counts[track.artistName, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }),
              top.value >= 2 || playlist.tracks.count <= 3 else { return nil }
        return top.key
    }
}

// MARK: - Playlist Detail View (premium)

struct PlaylistDetailView: View {
    let playlist: PlaylistManager.Playlist
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    private var currentPlaylist: PlaylistManager.Playlist {
        playlistManager.playlists.first { $0.id == playlist.id } ?? playlist
    }

    var body: some View {
        NavigationStack {
            Group {
                if currentPlaylist.tracks.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(.quaternary)
                                .frame(width: 70, height: 70)
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        Text("Playlist vide")
                            .font(.title3.weight(.semibold))
                        Text("Ajoute des morceaux depuis la\nrecherche ou les recommandations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Header
                            playlistHeader

                            // Tracks
                            LazyVStack(spacing: 0) {
                                ForEach(Array(currentPlaylist.tracks.enumerated()), id: \.element.id) { index, track in
                                    HStack(spacing: 10) {
                                        // Track number
                                        Text("\(index + 1)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 18)

                                        AsyncArtwork(
                                            url: track.artworkURL.flatMap { URL(string: $0) },
                                            size: 40,
                                            radius: 7
                                        )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(.callout.weight(.medium))
                                                .lineLimit(1)
                                            Text(track.artistName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        player.forcePlay(track: track.toiTunesTrack())
                                    }
                                    .contextMenu {
                                        Button {
                                            player.forcePlay(track: track.toiTunesTrack())
                                        } label: {
                                            Label("Ecouter", systemImage: "play.fill")
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            HapticManager.impact(.rigid)
                                            playlistManager.removeTrack(trackId: track.id, from: playlist.id)
                                        } label: {
                                            Label("Retirer", systemImage: "minus.circle")
                                        }
                                    }

                                    if index < currentPlaylist.tracks.count - 1 {
                                        Divider().padding(.leading, 84)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle(currentPlaylist.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var playlistHeader: some View {
        VStack(spacing: 12) {
            Text("\(currentPlaylist.trackCount) titre\(currentPlaylist.trackCount > 1 ? "s" : "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Play all
                Button {
                    HapticManager.impact(.medium)
                    if let first = currentPlaylist.tracks.first {
                        player.forcePlay(track: first.toiTunesTrack())
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                        Text("Lecture")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.tint, in: Capsule())
                }

                // Shuffle
                Button {
                    HapticManager.impact(.medium)
                    if let random = currentPlaylist.tracks.randomElement() {
                        player.forcePlay(track: random.toiTunesTrack())
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.caption.weight(.bold))
                        Text("Aleatoire")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }
}
