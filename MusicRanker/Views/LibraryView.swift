import SwiftUI
import CoreData

/// Bibliothèque V4 — Likes + Playlists + Surprends-moi
struct LibraryView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var moodManager: MoodManager

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

// MARK: - Playlists View (V4 premium)

struct PlaylistsView: View {
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var moodManager: MoodManager

    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var editingPlaylistId: String?
    @State private var editName = ""
    @State private var selectedPlaylist: PlaylistManager.Playlist?

    // Surprends-moi
    @State private var isGeneratingSurprise = false
    @State private var surprisePlaylistName: String?
    @State private var surpriseTracks: [iTunesTrack] = []
    @State private var showSurpriseResult = false
    @State private var shuffleRotation: Double = 0

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
        .sheet(isPresented: $showSurpriseResult) {
            SurpriseResultSheet(
                name: surprisePlaylistName ?? "Surprise Mix",
                tracks: surpriseTracks
            )
            .environmentObject(player)
            .environmentObject(playlistManager)
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

    // MARK: - Empty State

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

            Text("Crée ta première playlist ou laisse\nVIBELY te surprendre.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { showNewPlaylist = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("Créer")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(.tint, in: Capsule())
                }

                surpriseMeButton
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Playlists List

    private var playlistsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // Top actions row
                HStack(spacing: 10) {
                    createButton
                    surpriseMeButton
                }
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

    // MARK: - Surprends-moi Button

    private var surpriseMeButton: some View {
        Button {
            HapticManager.impact(.medium)
            generateSurprise()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(shuffleRotation))
                Text("Surprends-moi")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [.purple, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .opacity(isGeneratingSurprise ? 0.7 : 1)
        }
        .disabled(isGeneratingSurprise)
    }

    private func generateSurprise() {
        isGeneratingSurprise = true

        // Animate wand
        withAnimation(.spring(duration: 0.6).repeatCount(3, autoreverses: true)) {
            shuffleRotation = 20
        }

        Task {
            let profile = engine.buildTasteProfile()
            let result = await SurpriseMeGenerator.shared.generate(
                profile: profile,
                mood: moodManager.currentMood,
                count: 15
            )

            await MainActor.run {
                withAnimation(.spring(duration: 0.3)) {
                    shuffleRotation = 0
                    isGeneratingSurprise = false
                    surprisePlaylistName = result.name
                    surpriseTracks = result.tracks
                    showSurpriseResult = true
                }
                HapticManager.notification(.success)
            }
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { showNewPlaylist.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Text("Nouvelle")
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Field

    private var createField: some View {
        HStack(spacing: 8) {
            TextField("Nom de la playlist", text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            Button("Créer") {
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
            HapticManager.selection()
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

// MARK: - Surprise Result Sheet

struct SurpriseResultSheet: View {
    let name: String
    let tracks: [iTunesTrack]
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var playlistManager: PlaylistManager
    @Environment(\.dismiss) private var dismiss

    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.3), .pink.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 32))
                                .foregroundStyle(.purple)
                        }

                        Text(name)
                            .font(.title2.bold())

                        Text("\(tracks.count) morceaux générés par VIBELY")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            HapticManager.impact(.medium)
                            if let first = tracks.first {
                                player.forcePlay(track: first)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.caption.weight(.bold))
                                Text("Écouter")
                                    .font(.callout.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(.tint, in: Capsule())
                        }

                        Button {
                            HapticManager.notification(.success)
                            saveAsPlaylist()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                                    .font(.caption.weight(.bold))
                                Text(saved ? "Sauvegardée" : "Sauvegarder")
                                    .font(.callout.weight(.semibold))
                            }
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(.tint.opacity(0.12), in: Capsule())
                        }
                        .disabled(saved)
                    }
                    .padding(.horizontal, 16)

                    // Track list
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 20)

                                AsyncArtwork(
                                    url: track.artworkURL(size: 100),
                                    size: 42,
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

                                if let duration = track.formattedDuration {
                                    Text(duration)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.impact(.light)
                                player.forcePlay(track: track)
                            }

                            if index < tracks.count - 1 {
                                Divider().padding(.leading, 84)
                            }
                        }
                    }
                }
                .padding(.bottom, 80)
            }
            .navigationTitle("Surprise !")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func saveAsPlaylist() {
        playlistManager.createPlaylist(name: name)
        if let playlistId = playlistManager.playlists.first?.id {
            for track in tracks {
                playlistManager.addTrack(track, to: playlistId)
            }
        }
        withAnimation(.spring(duration: 0.3)) { saved = true }
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
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
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
            AsyncImage(url: URL(string: artworks[0])) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.15)
                }
            }
        } else {
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

// MARK: - Playlist Detail View (V4)

struct PlaylistDetailView: View {
    let playlist: PlaylistManager.Playlist
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var shuffleScale: CGFloat = 1

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
                                .fill(Color.gray.opacity(0.2))
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
                            playlistHeader

                            LazyVStack(spacing: 0) {
                                ForEach(Array(currentPlaylist.tracks.enumerated()), id: \.element.id) { index, track in
                                    HStack(spacing: 10) {
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

                // Shuffle with animation
                Button {
                    HapticManager.impact(.medium)
                    withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                        shuffleScale = 1.15
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(duration: 0.2)) {
                            shuffleScale = 1
                        }
                    }
                    if let random = currentPlaylist.tracks.randomElement() {
                        player.forcePlay(track: random.toiTunesTrack())
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.caption.weight(.bold))
                        Text("Aléatoire")
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .scaleEffect(shuffleScale)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }
}
