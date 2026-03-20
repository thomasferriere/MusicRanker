import SwiftUI
import CoreData

struct TasteProfileView: View {
    @EnvironmentObject private var engine: RecommendationEngine
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SwipedSongEntity.swipedAt, ascending: false)],
        animation: .default
    )
    private var allSwiped: FetchedResults<SwipedSongEntity>

    @State private var showResetAlert = false

    // MARK: - Computed

    private var likedCount: Int { allSwiped.filter(\.isLiked).count }
    private var dislikedCount: Int { allSwiped.filter { !$0.isLiked }.count }
    private var totalCount: Int { allSwiped.count }

    private var likeRate: Int {
        guard totalCount > 0 else { return 0 }
        return Int(Double(likedCount) / Double(totalCount) * 100)
    }

    private var topGenres: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for song in allSwiped where song.isLiked {
            if let genre = song.genre, !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    private var topArtists: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for song in allSwiped where song.isLiked {
            if let artist = song.artistName {
                counts[artist, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }

    private var recentActivity: [(day: String, count: Int)] {
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

        let orderedDays = [2, 3, 4, 5, 6, 7, 1] // Lun -> Dim
        return orderedDays.compactMap { day in
            var comp = DateComponents()
            comp.weekday = day
            guard let date = calendar.nextDate(after: Date(), matching: comp, matchingPolicy: .nextTime) else { return nil }
            let name = formatter.string(from: date).capitalized
            return (day: name, count: dayCounts[day] ?? 0)
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

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if likedCount > 0 {
                    // Musical identity card
                    identityCard
                        .padding(.top, 8)

                    // Stats row
                    statsRow

                    // Energy profile
                    energySection

                    // Top genres
                    if !topGenres.isEmpty {
                        genresSection
                    }

                    // Top artists
                    if !topArtists.isEmpty {
                        artistsSection
                    }

                    // Activity
                    activitySection

                    // Streak
                    if listenStreak > 0 {
                        streakBadge
                    }
                } else {
                    emptyProfile
                }

                // Reset
                if totalCount > 0 {
                    resetButton
                        .padding(.top, 8)
                }
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
    }

    // MARK: - Identity Card

    private var identityCard: some View {
        let profile = engine.buildTasteProfile()
        let energy = profile.averageEnergy
        let mainGenre = topGenres.first?.name ?? "Musique"
        let persona: (title: String, subtitle: String, gradient: [Color])

        if energy >= 0.75 {
            persona = ("Flamme Musicale", "Ton énergie est explosive", [.red, .orange])
        } else if energy >= 0.55 {
            persona = ("Esprit Dynamique", "Tu vibres avec le rythme", [.orange, .yellow])
        } else if energy >= 0.35 {
            persona = ("Ame Équilibrée", "Tu navigue entre calme et énergie", [.teal, .cyan])
        } else {
            persona = ("Voyageur Zen", "La sérénité guide tes écoutes", [.indigo, .purple])
        }

        return VStack(spacing: 14) {
            // Gradient header
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
                    Text("\(topArtists.first?.name ?? "—")")
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

    // MARK: - Energy

    private var energySection: some View {
        let profile = engine.buildTasteProfile()
        let energy = profile.averageEnergy
        let label: String
        let icon: String
        let color: Color

        switch energy {
        case 0..<0.35:
            label = "Chill & Relax"
            icon = "moon.stars.fill"
            color = .indigo
        case 0.35..<0.55:
            label = "Équilibré"
            icon = "equal.circle.fill"
            color = .teal
        case 0.55..<0.75:
            label = "Dynamique"
            icon = "bolt.fill"
            color = .orange
        default:
            label = "Haute énergie"
            icon = "flame.fill"
            color = .red
        }

        return sectionCard(title: "Ton énergie musicale", icon: "waveform.path.ecg") {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.headline)

                    // Energy bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
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
        sectionCard(title: "Tes genres", icon: "guitars.fill") {
            VStack(spacing: 10) {
                ForEach(Array(topGenres.enumerated()), id: \.element.name) { _, genre in
                    HStack(spacing: 10) {
                        Text(genre.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)

                        GenreBarView(
                            count: genre.count,
                            maxCount: topGenres.first?.count ?? 1
                        )
                    }
                }
            }
        }
    }

    // MARK: - Artists

    private var artistsSection: some View {
        sectionCard(title: "Tes artistes", icon: "music.mic") {
            VStack(spacing: 0) {
                ForEach(Array(topArtists.enumerated()), id: \.element.name) { index, artist in
                    HStack(spacing: 12) {
                        // Rank badge
                        ZStack {
                            if index < 3 {
                                Circle()
                                    .fill(medalColor(index).opacity(0.15))
                                    .frame(width: 28, height: 28)
                            }
                            Text("\(index + 1)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(index < 3 ? medalColor(index) : .secondary)
                        }
                        .frame(width: 28)

                        Text(artist.name)
                            .font(.callout.weight(index < 3 ? .semibold : .regular))
                            .lineLimit(1)

                        Spacer()

                        Text("\(artist.count) like\(artist.count > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)

                    if index < topArtists.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        let maxDay = recentActivity.map(\.count).max() ?? 1

        return sectionCard(title: "Ton activité", icon: "chart.bar.fill") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(recentActivity, id: \.day) { item in
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
