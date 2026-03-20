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

    private var likedCount: Int { allSwiped.filter(\.isLiked).count }
    private var dislikedCount: Int { allSwiped.filter { !$0.isLiked }.count }
    private var totalCount: Int { allSwiped.count }

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

    private var likeRate: Int {
        guard totalCount > 0 else { return 0 }
        return Int(Double(likedCount) / Double(totalCount) * 100)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Stats cards
                statsSection
                    .padding(.top, 8)

                if likedCount > 0 {
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
                } else {
                    emptyProfile
                }

                // Reset
                if totalCount > 0 {
                    resetButton
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

    // MARK: - Stats

    private var statsSection: some View {
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.headline)

                    // Energy bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                            Capsule()
                                .fill(color)
                                .frame(width: geo.size.width * energy)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    // MARK: - Genres

    private var genresSection: some View {
        sectionCard(title: "Tes genres", icon: "guitars.fill") {
            FlowLayout(spacing: 8) {
                ForEach(topGenres, id: \.name) { genre in
                    GenreChip(
                        name: genre.name,
                        count: genre.count,
                        maxCount: topGenres.first?.count ?? 1
                    )
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
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(index < 3 ? .tint : .secondary)
                            .frame(width: 22, alignment: .trailing)

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
}

// MARK: - Genre Chip

struct GenreChip: View {
    let name: String
    let count: Int
    let maxCount: Int

    private var intensity: Double { Double(count) / Double(max(maxCount, 1)) }

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
            Text("(\(count))")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.08 + intensity * 0.18), in: Capsule())
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
