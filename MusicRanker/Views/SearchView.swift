import SwiftUI

/// Search V4 — tendances, historique, suggestions, filtres mood
struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var trendingService: TrendingService
    @EnvironmentObject private var moodManager: MoodManager

    @State private var selectedTrack: iTunesTrack?
    @State private var playlistTarget: iTunesTrack?
    @State private var selectedFilter: SearchFilter = .all

    enum SearchFilter: String, CaseIterable {
        case all = "Tout"
        case title = "Titre"
        case artist = "Artiste"
        case mood = "Mood"
    }

    var body: some View {
        Group {
            if vm.query.isEmpty && vm.results.isEmpty {
                historyAndSuggestions
            } else if vm.isSearching {
                loadingState
            } else if vm.results.isEmpty && !vm.query.isEmpty {
                ContentUnavailableView.search(text: vm.query)
            } else {
                resultsList
            }
        }
        .searchable(text: $vm.query, prompt: "Artiste, titre, album...")
        .onChange(of: vm.query) { _, _ in
            vm.updateSuggestions()
            vm.searchDebounced()
        }
        .onSubmit(of: .search) {
            Task { await vm.search() }
        }
        .sheet(item: $selectedTrack) { track in
            TrackDetailView(track: track)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $playlistTarget) { track in
            AddToPlaylistSheet(track: track)
                .environmentObject(playlistManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - History & Suggestions

    private var historyAndSuggestions: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Mood quick search
                moodQuickSearch
                    .padding(.top, 8)

                // Quick categories
                quickCategories

                // Trending suggestions
                if !trendingService.trendingTracks.isEmpty {
                    trendingSuggestions
                }

                // Recent searches
                if !vm.searchHistory.isEmpty {
                    recentSearches
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Mood Quick Search

    private var moodQuickSearch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recherche par mood")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MoodManager.Mood.allCases.filter { $0 != .none }, id: \.self) { mood in
                        Button {
                            HapticManager.selection()
                            vm.query = mood.searchTerms.first ?? mood.rawValue
                            Task { await vm.search() }
                        } label: {
                            HStack(spacing: 6) {
                                Text(mood.emoji)
                                    .font(.callout)
                                Text(mood.rawValue.capitalized)
                                    .font(.callout.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: mood.gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ).opacity(0.2),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Trending Suggestions

    private var trendingSuggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.callout)
                    .foregroundStyle(.tint)
                Text("Tendances du moment")
                    .font(.headline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(trendingService.trendingTracks.prefix(8)) { track in
                        Button {
                            HapticManager.impact(.light)
                            player.forcePlay(track: track)
                        } label: {
                            HStack(spacing: 10) {
                                AsyncArtwork(
                                    url: track.artworkURL(size: 80),
                                    size: 44,
                                    radius: 8
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(track.artistName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Recent Searches

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recherches récentes")
                    .font(.headline)
                Spacer()
                Button("Effacer") {
                    vm.clearHistory()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(vm.searchHistory.prefix(10), id: \.self) { term in
                    Button {
                        vm.query = term
                        Task { await vm.search() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            Text(term)
                                .font(.callout)
                                .foregroundStyle(.primary)

                            Spacer()

                            Button {
                                vm.removeFromHistory(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    Divider().opacity(0.3)
                }
            }
        }
    }

    // MARK: - Quick Categories

    private var quickCategories: some View {
        let categories = [
            ("Pop", "star.fill", Color.pink),
            ("Rap FR", "music.mic", Color.purple),
            ("R&B", "heart.fill", Color.red),
            ("Électro", "bolt.fill", Color.cyan),
            ("Rock", "guitars.fill", Color.orange),
            ("K-Pop", "sparkles", Color.blue),
            ("Jazz", "pianokeys", Color.yellow),
            ("Afrobeats", "globe.americas.fill", Color.green),
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Explorer par genre")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(categories, id: \.0) { name, icon, color in
                    Button {
                        vm.query = name
                        Task { await vm.search() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.callout)
                                .foregroundStyle(color)
                            Text(name)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SearchFilter.allCases, id: \.self) { filter in
                            Button {
                                HapticManager.selection()
                                withAnimation(.spring(duration: 0.2)) {
                                    selectedFilter = filter
                                }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedFilter == filter ? Color.accentColor : Color.gray.opacity(0.15),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedFilter == filter ? .white : .primary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                HStack {
                    Text("\(vm.results.count) résultat\(vm.results.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                ForEach(vm.results) { track in
                    SearchResultRow(track: track)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.impact(.light)
                            player.forcePlay(track: track)
                        }
                        .contextMenu {
                            Button {
                                player.forcePlay(track: track)
                            } label: {
                                Label("Écouter", systemImage: "play.fill")
                            }

                            Button {
                                HapticManager.notification(.success)
                                engine.saveFeedback(track: track, liked: true)
                            } label: {
                                Label(
                                    engine.isTrackLiked(id: track.id) ? "Déjà liké" : "J'aime",
                                    systemImage: engine.isTrackLiked(id: track.id) ? "heart.fill" : "heart"
                                )
                            }

                            Button {
                                playlistTarget = track
                            } label: {
                                Label("Ajouter à une playlist", systemImage: "text.badge.plus")
                            }

                            Divider()

                            Button {
                                selectedTrack = track
                            } label: {
                                Label("Détails", systemImage: "info.circle")
                            }

                            Menu("Ouvrir dans...") {
                                ForEach(MusicPlatform.allCases) { platform in
                                    Button {
                                        ExternalMusicOpener.open(
                                            platform: platform,
                                            title: track.title,
                                            artist: track.artistName
                                        )
                                    } label: {
                                        Label(platform.rawValue, systemImage: platform.icon)
                                    }
                                }
                            }
                        }

                    if track.id != vm.results.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Recherche en cours...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let track: iTunesTrack
    @EnvironmentObject private var player: AudioPlayerManager

    private var isPlaying: Bool { player.isCurrentlyPlaying(id: track.id) }

    var body: some View {
        HStack(spacing: 12) {
            AsyncArtwork(
                url: track.artworkURL(size: 120),
                size: 52,
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
                Text(track.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(track.artistName)
                    if let album = track.albumName {
                        Text("·")
                        Text(album)
                    }
                }
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
    }
}

// MARK: - Add to Playlist Sheet

struct AddToPlaylistSheet: View {
    let track: iTunesTrack
    @EnvironmentObject private var playlistManager: PlaylistManager
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false

    var body: some View {
        NavigationStack {
            List {
                if playlistManager.playlists.isEmpty && !showNewPlaylist {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                            Text("Aucune playlist")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }

                Section {
                    Button {
                        withAnimation { showNewPlaylist = true }
                    } label: {
                        Label("Nouvelle playlist", systemImage: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }

                    if showNewPlaylist {
                        HStack {
                            TextField("Nom de la playlist", text: $newPlaylistName)
                                .textFieldStyle(.roundedBorder)
                            Button("Créer") {
                                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                playlistManager.createPlaylist(name: name)
                                if let id = playlistManager.playlists.first?.id {
                                    playlistManager.addTrack(track, to: id)
                                }
                                HapticManager.notification(.success)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                if !playlistManager.playlists.isEmpty {
                    Section("Tes playlists") {
                        ForEach(playlistManager.playlists) { playlist in
                            let alreadyIn = playlistManager.isTrackInPlaylist(trackId: track.id, playlistId: playlist.id)
                            Button {
                                if !alreadyIn {
                                    playlistManager.addTrack(track, to: playlist.id)
                                    HapticManager.notification(.success)
                                }
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.callout.weight(.medium))
                                        Text("\(playlist.trackCount) titre\(playlist.trackCount > 1 ? "s" : "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if alreadyIn {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .disabled(alreadyIn)
                        }
                    }
                }
            }
            .navigationTitle("Ajouter à une playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}
