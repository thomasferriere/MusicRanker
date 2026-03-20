import SwiftUI
import CoreData

struct TasteProfileView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @EnvironmentObject private var moodManager: MoodManager
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SwipedSongEntity.swipedAt, ascending: false)],
        animation: .none
    )
    private var allSwiped: FetchedResults<SwipedSongEntity>

    @State private var showResetAlert = false
    @StateObject private var matchService = MusicalMatchService.shared

    // MARK: - Stable Computed Data

    private struct StableGenre: Identifiable {
        let id: String
        let name: String
        let count: Int
    }

    private struct StableArtist: Identifiable {
        let id: String
        let name: String
        let count: Int
        let rank: Int
    }

    private struct StableDay: Identifiable {
        let id: Int
        let day: String
        let count: Int
    }

    // MARK: - Computed

    private var likedCount: Int { allSwiped.filter(\.isLiked).count }
    private var dislikedCount: Int { allSwiped.filter { !$0.isLiked }.count }
    private var totalCount: Int { allSwiped.count }

    private var likeRate: Int {
        guard totalCount > 0 else { return 0 }
        return Int(Double(likedCount) / Double(totalCount) * 100)
    }

    private var stableGenres: [StableGenre] {
        var counts: [String: Int] = [:]
        for song in allSwiped where song.isLiked {
            if let genre = song.genre, !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(8).map {
            StableGenre(id: $0.key, name: $0.key, count: $0.value)
        }
    }

    private var stableArtists: [StableArtist] {
        var counts: [String: Int] = [:]
        for song in allSwiped where song.isLiked {
            if let artist = song.artistName {
                counts[artist, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).enumerated().map { index, item in
            StableArtist(id: item.key, name: item.key, count: item.value, rank: index)
        }
    }

    private var stableActivity: [StableDay] {
        let liked = allSwiped.filter(\.isLiked)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"

        var dayCounts: [Int: Int] = [:]
        for song in liked {
            guard let date = song.swipedAt else { continue }
            let weekday = calendar.component(.weekday, from: date)
            dayCounts[weekday, default: 0] += 1
        }

        let orderedDays = [2, 3, 4, 5, 6, 7, 1]
        return orderedDays.compactMap { day in
            var comp = DateComponents()
            comp.weekday = day
            guard let date = calendar.nextDate(after: Date(), matching: comp, matchingPolicy: .nextTime) else { return nil }
            let name = formatter.string(from: date).capitalized
            return StableDay(id: day, day: name, count: dayCounts[day] ?? 0)
        }
    }

    private var listenStreak: Int {
        let calendar = Calendar.current
        let dates = Set(allSwiped.compactMap { $0.swipedAt }.map { calendar.startOfDay(for: $0) })
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        while dates.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    /// Top tracks of the month
    private var topTracksMonth: [SwipedSongEntity] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return allSwiped.filter { $0.isLiked && ($0.swipedAt ?? Date.distantPast) >= startOfMonth }
            .prefix(5)
            .map { $0 }
    }

    /// Achievements / Badges
    private var earnedBadges: [(icon: String, title: String, color: Color)] {
        var badges: [(String, String, Color)] = []
        if likedCount >= 10 { badges.append(("heart.fill", "10 likes", .pink)) }
        if likedCount >= 50 { badges.append(("star.fill", "50 likes", .yellow)) }
        if likedCount >= 100 { badges.append(("crown.fill", "100 likes", .orange)) }
        if stableGenres.count >= 5 { badges.append(("globe", "5 genres", .cyan)) }
        if listenStreak >= 3 { badges.append(("flame.fill", "3j streak", .red)) }
        if listenStreak >= 7 { badges.append(("flame.circle.fill", "7j streak", .orange)) }
        if totalCount >= 100 { badges.append(("headphones", "100 écoutes", .blue)) }
        if stableArtists.count >= 8 { badges.append(("music.mic", "8+ artistes", .purple)) }
        return badges
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if likedCount > 0 {
                    identityCard
                        .padding(.top, 8)

                    // ADN Musical — Radar Chart
                    radarSection

                    statsRow

                    // Badges / Achievements
                    if !earnedBadges.isEmpty {
                        badgesSection
                    }

                    energySection

                    if !stableGenres.isEmpty {
                        genresSection
                    }

                    if !stableArtists.isEmpty {
                        artistsSection
                    }

                    // Top tracks du mois
                    if !topTracksMonth.isEmpty {
                        topTracksSection
                    }

                    activitySection

                    if listenStreak > 0 {
                        streakBadge
                    }

                    // Social Match
                    socialMatchSection
                } else {
                    emptyProfile
                }

                if totalCount > 0 {
                    resetButton
                        .padding(.top, 8)
                }

                // App branding
                Text("VIBELY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.15))
                    .tracking(4)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .alert("Réinitialiser ?", isPresented: $showResetAlert) {
            Button("Annuler", role: .cancel) {}
            Button("Réinitialiser", role: .destructive) {
                HapticManager.notification(.warning)
                engine.resetAll()
            }
        } message: {
            Text("Toutes tes données seront supprimées. L'algorithme recommencera de zéro.")
        }
        .task {
            let profile = engine.buildTasteProfile()
            await matchService.loadMatches(from: profile)
        }
    }

    // MARK: - Identity Card

    private var identityCard: some View {
        let profile = engine.buildTasteProfile()
        let energy = profile.averageEnergy
        let mainGenre = stableGenres.first?.name ?? "Musique"
        let persona: (title: String, subtitle: String, gradient: [Color])

        if energy >= 0.75 {
            persona = ("Flamme Musicale", "Ton énergie est explosive", [.red, .orange])
        } else if energy >= 0.55 {
            persona = ("Esprit Dynamique", "Tu vibres avec le rythme", [.orange, .yellow])
        } else if energy >= 0.35 {
            persona = ("Âme Équilibrée", "Tu navigues entre calme et énergie", [.teal, .cyan])
        } else {
            persona = ("Voyageur Zen", "La sérénité guide tes écoutes", [.indigo, .purple])
        }

        return VStack(spacing: 14) {
            ZStack {
                LinearGradient(colors: persona.gradient + [.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .opacity(0.3)

                VStack(spacing: 6) {
                    Text(persona.title)
                        .font(.title2.bold())
                    Text(persona.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text(mainGenre)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text("Genre favori")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider().frame(height: 24)

                VStack(spacing: 2) {
                    Text(stableArtists.first?.name ?? "—")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.pink)
                        .lineLimit(1)
                    Text("Artiste #1")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider().frame(height: 24)

                VStack(spacing: 2) {
                    Text("\(likedCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                    Text("Likes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Radar Chart (ADN Musical)

    private var radarSection: some View {
        sectionCard(title: "ADN Musical", icon: "circle.hexagongrid.fill") {
            let profile = engine.buildTasteProfile()
            let axes = buildRadarAxes(profile: profile)

            VStack(spacing: 12) {
                RadarChartView(axes: axes)
                    .frame(height: 200)

                // Legend
                FlowLayout(spacing: 6) {
                    ForEach(axes.indices, id: \.self) { i in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                            Text(axes[i].label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func buildRadarAxes(profile: RecommendationEngine.TasteProfile) -> [RadarAxis] {
        let energy = profile.averageEnergy
        let genreDiversity = min(1.0, Double(profile.topGenres.count) / 6.0)
        let artistLoyalty = profile.topArtists.isEmpty ? 0 : min(1.0, Double(profile.topArtists.first?.count ?? 0) / 10.0)
        let popAffinity = profile.genreWeights["Pop"] ?? 0
        let urbanAffinity = max(
            profile.genreWeights["Hip-Hop/Rap"] ?? 0,
            profile.genreWeights["R&B/Soul"] ?? 0
        )
        let explorationRate = genreDiversity > 0.5 ? 0.7 + Double.random(in: 0...0.3) : 0.3 + Double.random(in: 0...0.3)

        return [
            RadarAxis(label: "Énergie", value: energy),
            RadarAxis(label: "Diversité", value: genreDiversity),
            RadarAxis(label: "Fidélité", value: artistLoyalty),
            RadarAxis(label: "Pop", value: popAffinity),
            RadarAxis(label: "Urban", value: urbanAffinity),
            RadarAxis(label: "Exploration", value: min(1.0, explorationRate)),
        ]
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(totalCount)", label: "Écoutés", icon: "headphones", color: .blue)
            statCard(value: "\(likedCount)", label: "Likés", icon: "heart.fill", color: .green)
            statCard(value: "\(likeRate)%", label: "Taux like", icon: "chart.bar.fill", color: .purple)
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Badges

    private var badgesSection: some View {
        sectionCard(title: "Achievements", icon: "trophy.fill") {
            FlowLayout(spacing: 8) {
                ForEach(earnedBadges.indices, id: \.self) { i in
                    let badge = earnedBadges[i]
                    HStack(spacing: 6) {
                        Image(systemName: badge.icon)
                            .font(.caption2)
                            .foregroundStyle(badge.color)
                        Text(badge.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(badge.color.opacity(0.12), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(badge.color.opacity(0.2), lineWidth: 1)
                    }
                }
            }
        }
    }

    // MARK: - Energy

    private var energySection: some View {
        let profile = engine.buildTasteProfile()
        let energy = profile.averageEnergy
        let label: String
        let icon: String
        let color: Color

        switch energy {
        case 0..<0.35:
            label = "Chill & Relax"; icon = "moon.stars.fill"; color = .indigo
        case 0.35..<0.55:
            label = "Équilibré"; icon = "equal.circle.fill"; color = .teal
        case 0.55..<0.75:
            label = "Dynamique"; icon = "bolt.fill"; color = .orange
        default:
            label = "Haute énergie"; icon = "flame.fill"; color = .red
        }

        return sectionCard(title: "Ton énergie musicale", icon: "waveform.path.ecg") {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.headline)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.gray.opacity(0.2))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [color.opacity(0.7), color],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * energy)
                        }
                    }
                    .frame(height: 8)

                    Text("\(Int(energy * 100))% d'énergie moyenne")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Genres

    private var genresSection: some View {
        let maxCount = stableGenres.first?.count ?? 1

        return sectionCard(title: "Tes genres", icon: "guitars.fill") {
            VStack(spacing: 10) {
                ForEach(stableGenres) { genre in
                    HStack(spacing: 10) {
                        Text(genre.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)

                        GenreBarView(count: genre.count, maxCount: maxCount)
                    }
                }
            }
        }
    }

    // MARK: - Artists

    private var artistsSection: some View {
        sectionCard(title: "Tes artistes", icon: "music.mic") {
            VStack(spacing: 0) {
                ForEach(stableArtists) { artist in
                    HStack(spacing: 12) {
                        ZStack {
                            if artist.rank < 3 {
                                Circle()
                                    .fill(medalColor(artist.rank).opacity(0.15))
                                    .frame(width: 28, height: 28)
                            }
                            Text("\(artist.rank + 1)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(artist.rank < 3 ? medalColor(artist.rank) : .secondary)
                        }
                        .frame(width: 28)

                        Text(artist.name)
                            .font(.callout.weight(artist.rank < 3 ? .semibold : .regular))
                            .lineLimit(1)

                        Spacer()

                        Text("\(artist.count) like\(artist.count > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)

                    if artist.rank < stableArtists.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    // MARK: - Top Tracks du Mois

    private var topTracksSection: some View {
        sectionCard(title: "Top du mois", icon: "calendar") {
            VStack(spacing: 0) {
                ForEach(Array(topTracksMonth.enumerated()), id: \.element.objectID) { index, song in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        if let url = song.artworkURL.flatMap({ URL(string: $0) }) {
                            AsyncArtwork(url: url, size: 36, radius: 6)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title ?? "—")
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(song.artistName ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        let maxDay = stableActivity.map(\.count).max() ?? 1

        return sectionCard(title: "Ton activité", icon: "chart.bar.fill") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(stableActivity) { item in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.gradient)
                            .frame(
                                height: max(4, CGFloat(item.count) / CGFloat(max(maxDay, 1)) * 60)
                            )

                        Text(item.day)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
        }
    }

    // MARK: - Streak

    private var streakBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(listenStreak) jour\(listenStreak > 1 ? "s" : "") de suite")
                    .font(.callout.weight(.semibold))
                Text("Continue comme ça !")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.1), .clear],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Social Match

    private var socialMatchSection: some View {
        sectionCard(title: "Match Musical", icon: "person.2.fill") {
            if matchService.isLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(.secondary)
                    Spacer()
                }
                .padding(.vertical, 16)
            } else if matchService.matches.isEmpty {
                Text("Pas encore de matches disponibles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(matchService.matches.prefix(5)) { match in
                        HStack(spacing: 12) {
                            // Avatar
                            Text(match.avatarEmoji)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(match.name)
                                        .font(.callout.weight(.semibold))
                                    if let badge = match.badge {
                                        Text(badge.rawValue)
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.tint.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.tint)
                                    }
                                }
                                Text(match.topGenres.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Compatibility score
                            Text("\(match.compatibility)%")
                                .font(.headline.bold().monospacedDigit())
                                .foregroundStyle(compatibilityColor(match.compatibility))
                        }
                        .padding(.vertical, 8)

                        if match.id != matchService.matches.prefix(5).last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
    }

    private func compatibilityColor(_ score: Int) -> Color {
        switch score {
        case 80...: .green
        case 60..<80: .orange
        default: .secondary
        }
    }

    // MARK: - Empty Profile

    private var emptyProfile: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Pas encore de profil")
                .font(.title3.weight(.semibold))
            Text("Like des morceaux dans Découvrir pour construire ton profil musical.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 32)
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            showResetAlert = true
        } label: {
            Label("Réinitialiser tout", systemImage: "arrow.counterclockwise")
                .font(.footnote)
                .foregroundStyle(.red)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func medalColor(_ index: Int) -> Color {
        switch index {
        case 0: .yellow
        case 1: .gray
        case 2: .orange
        default: .secondary
        }
    }
}

// MARK: - Radar Chart View

struct RadarAxis {
    let label: String
    let value: Double // 0...1
}

struct RadarChartView: View {
    let axes: [RadarAxis]
    let gridLevels: Int = 4

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 30

            ZStack {
                // Grid circles
                ForEach(1...gridLevels, id: \.self) { level in
                    let r = radius * CGFloat(level) / CGFloat(gridLevels)
                    polygonPath(center: center, radius: r, sides: axes.count)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }

                // Axis lines
                ForEach(0..<axes.count, id: \.self) { i in
                    let angle = angleFor(index: i)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: pointAt(center: center, radius: radius, angle: angle))
                    }
                    .stroke(.white.opacity(0.06), lineWidth: 1)
                }

                // Filled polygon
                let dataPath = dataPolygonPath(center: center, radius: radius)
                dataPath
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.3), .purple.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                dataPath
                    .stroke(Color.accentColor, lineWidth: 2)

                // Data points
                ForEach(axes.indices, id: \.self) { i in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .position(
                            pointAt(
                                center: center,
                                radius: radius * CGFloat(axes[i].value),
                                angle: angleFor(index: i)
                            )
                        )
                }

                // Labels
                ForEach(axes.indices, id: \.self) { i in
                    Text(axes[i].label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .position(
                            pointAt(
                                center: center,
                                radius: radius + 20,
                                angle: angleFor(index: i)
                            )
                        )
                }
            }
        }
    }

    private func angleFor(index: Int) -> Double {
        let slice = 2 * .pi / Double(axes.count)
        return slice * Double(index) - .pi / 2
    }

    private func pointAt(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(Foundation.cos(angle)),
            y: center.y + radius * CGFloat(Foundation.sin(angle))
        )
    }

    private func polygonPath(center: CGPoint, radius: CGFloat, sides: Int) -> Path {
        Path { path in
            for i in 0..<sides {
                let angle = angleFor(index: i)
                let pt = pointAt(center: center, radius: radius, angle: angle)
                if i == 0 { path.move(to: pt) }
                else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }
    }

    private func dataPolygonPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            for i in 0..<axes.count {
                let angle = angleFor(index: i)
                let r = radius * CGFloat(axes[i].value)
                let pt = pointAt(center: center, radius: r, angle: angle)
                if i == 0 { path.move(to: pt) }
                else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }
    }
}

// MARK: - Genre Bar View

struct GenreBarView: View {
    let count: Int
    let maxCount: Int

    private var ratio: CGFloat {
        CGFloat(count) / CGFloat(max(maxCount, 1))
    }

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.accentColor.gradient)
                .frame(width: max(4, geo.size.width * ratio), height: 20)
                .overlay(alignment: .trailing) {
                    Text("\(count)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.trailing, 6)
                        .opacity(ratio > 0.2 ? 1 : 0)
                }
        }
        .frame(height: 20)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return ArrangeResult(positions: positions, size: CGSize(width: maxWidth, height: y + rowHeight))
    }
}
