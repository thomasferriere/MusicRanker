import SwiftUI
import CoreData

/// Bibliothèque premium — Likes + Playlists
struct LibraryView: View {
    @State private var selectedSection: LibrarySection = .likes
    @State private var searchText = ""

    enum LibrarySection: String, CaseIterable {
        case likes = "Likes"
        case playlists = "Playlists"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segment picker
            Picker("Section", selection: $selectedSection) {
                ForEach(LibrarySection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

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

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.tint.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "music.note.list")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint.opacity(0.6))
            }

            Text("Aucune playlist")
                .font(.title3.weight(.semibold))

            Text("Crée ta première playlist pour organiser\ntes morceaux préférés.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation(.spring(duration: 0.3)) { showNewPlaylist = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.callout.weight(.bold))
                    Text("Créer une playlist")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
                .background(.tint, in: Capsule())
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - List

    private var playlistsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Create new
                Button {
                    withAnimation(.spring(duration: 0.3)) { showNewPlaylist.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.tint.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: "plus")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                        Text("Nouvelle playlist")
                            .font(.callout.weight(.medium))
                        Spacer()
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)

                // Create field
                if showNewPlaylist {
                    HStack(spacing: 10) {
                        TextField("Nom de la playlist", text: $newPlaylistName)
                            .textFieldStyle(.roundedBorder)
                        Button("Créer") {
                            let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            playlistManager.createPlaylist(name: name)
                            newPlaylistName = ""
                            showNewPlaylist = false
                            HapticManager.notification(.success)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Stats
                if !playlistManager.playlists.isEmpty {
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
                    .padding(.horizontal, 20)
                }

                // Playlist cards
                LazyVStack(spacing: 10) {
                    ForEach(playlistManager.playlists) { playlist in
                        PremiumPlaylistCard(playlist: playlist) {
                            selectedPlaylist = playlist
                        }
                        .contextMenu {
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
                                Label("Lecture aléatoire", systemImage: "shuffle")
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
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Premium Playlist Card

struct PremiumPlaylistCard: View {
    let playlist: PlaylistManager.Playlist
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Artwork mosaic or placeholder
                artworkMosaic
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text("\(playlist.trackCount) titre\(playlist.trackCount > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let firstArtist = playlist.tracks.first?.artistName {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(firstArtist)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artworkMosaic: some View {
        let artworks = playlist.tracks.prefix(4).compactMap { $0.artworkURL }

        if artworks.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else if artworks.count < 4 {
            // Single artwork
            AsyncImage(url: URL(string: artworks[0])) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.2)
                }
            }
        } else {
            // 2x2 grid
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    mosaicTile(artworks[0])
                    mosaicTile(artworks[1])
                }
                HStack(spacing: 1) {
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
                Color.gray.opacity(0.2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
                                .frame(width: 80, height: 80)
                            Image(systemName: "music.note")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                        Text("Playlist vide")
                            .font(.title3.weight(.semibold))
                        Text("Ajoute des morceaux depuis la recherche\nou les recommandations.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
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
                                    HStack(spacing: 12) {
                                        // Track number
                                        Text("\(index + 1)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 20)

                                        AsyncArtwork(
                                            url: track.artworkURL.flatMap { URL(string: $0) },
                                            size: 44,
                                            radius: 8
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
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        player.forcePlay(track: track.toiTunesTrack())
                                    }
                                    .contextMenu {
                                        Button {
                                            player.forcePlay(track: track.toiTunesTrack())
                                        } label: {
                                            Label("Écouter", systemImage: "play.fill")
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
                                        Divider().padding(.leading, 92)
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
        VStack(spacing: 16) {
            Text("\(currentPlaylist.trackCount) titre\(currentPlaylist.trackCount > 1 ? "s" : "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                // Play all
                Button {
                    HapticManager.impact(.medium)
                    if let first = currentPlaylist.tracks.first {
                        player.forcePlay(track: first.toiTunesTrack())
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.callout.weight(.bold))
                        Text("Lecture")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.tint, in: Capsule())
                }

                // Shuffle
                Button {
                    HapticManager.impact(.medium)
                    if let random = currentPlaylist.tracks.randomElement() {
                        player.forcePlay(track: random.toiTunesTrack())
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "shuffle")
                            .font(.callout.weight(.bold))
                        Text("Aléatoire")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.tint.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
    }
}
