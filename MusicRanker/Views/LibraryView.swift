import SwiftUI
import CoreData

/// Bibliothèque: Likes + Playlists combined
struct LibraryView: View {
    @State private var selectedSection: LibrarySection = .likes

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
            .padding(.bottom, 4)

            switch selectedSection {
            case .likes:
                LikedSongsView()
            case .playlists:
                PlaylistsView()
            }
        }
    }
}

// MARK: - Playlists View

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
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("Aucune playlist")
                .font(.title3.weight(.semibold))

            Text("Crée ta première playlist pour organiser tes morceaux préférés.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                withAnimation { showNewPlaylist = true }
            } label: {
                Label("Créer une playlist", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.tint, in: Capsule())
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - List

    private var playlistsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // New playlist button
                Button {
                    withAnimation { showNewPlaylist = true }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        Text("Nouvelle playlist")
                            .font(.callout.weight(.medium))
                        Spacer()
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)

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

                        Button("Annuler") {
                            newPlaylistName = ""
                            showNewPlaylist = false
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Playlist cards
                LazyVStack(spacing: 10) {
                    ForEach(playlistManager.playlists) { playlist in
                        PlaylistCard(playlist: playlist) {
                            selectedPlaylist = playlist
                        }
                        .contextMenu {
                            Button {
                                editingPlaylistId = playlist.id
                                editName = playlist.name
                            } label: {
                                Label("Renommer", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                HapticManager.notification(.warning)
                                withAnimation {
                                    playlistManager.deletePlaylist(id: playlist.id)
                                }
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
}

// MARK: - Playlist Card

struct PlaylistCard: View {
    let playlist: PlaylistManager.Playlist
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Artwork grid or placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)

                    if playlist.tracks.isEmpty {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        // Show first artwork
                        let firstArtwork = playlist.tracks.first?.artworkURL
                        AsyncArtwork(
                            url: firstArtwork.flatMap { URL(string: $0) },
                            size: 56,
                            radius: 10
                        )
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Text("\(playlist.trackCount) titre\(playlist.trackCount > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
}

// MARK: - Playlist Detail View

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
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Playlist vide")
                            .font(.title3.weight(.semibold))
                        Text("Ajoute des morceaux depuis la recherche ou Découvrir.")
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
                            VStack(spacing: 12) {
                                Text("\(currentPlaylist.trackCount) titre\(currentPlaylist.trackCount > 1 ? "s" : "")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                // Shuffle button
                                Button {
                                    HapticManager.impact(.medium)
                                    if let random = currentPlaylist.tracks.randomElement() {
                                        player.forcePlay(track: random.toiTunesTrack())
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "shuffle")
                                            .font(.callout.weight(.bold))
                                        Text("Shuffle")
                                            .font(.callout.weight(.semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 10)
                                    .background(.tint, in: Capsule())
                                }
                            }
                            .padding(.vertical, 16)

                            // Tracks
                            LazyVStack(spacing: 0) {
                                ForEach(currentPlaylist.tracks) { track in
                                    HStack(spacing: 12) {
                                        AsyncArtwork(
                                            url: track.artworkURL.flatMap { URL(string: $0) },
                                            size: 48,
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
                                        Button(role: .destructive) {
                                            HapticManager.impact(.rigid)
                                            playlistManager.removeTrack(trackId: track.id, from: playlist.id)
                                        } label: {
                                            Label("Retirer", systemImage: "minus.circle")
                                        }
                                    }

                                    Divider().padding(.leading, 76)
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
}
